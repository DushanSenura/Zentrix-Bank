import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'api_exceptions.dart';
import 'log_sanitizer.dart';
import 'service_status.dart';
import 'token_authority.dart';

typedef Json = Map<String, dynamic>;

String _randomId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// A fresh opaque key for one logical payment attempt; resending it never pays twice.
String newIdempotencyKey() => _randomId();

/// True when [der] hashes to one of [pins]. Exposed so the comparison can be unit-tested.
bool certificateMatchesPins(List<int> der, List<String> pins) => pins.contains(sha256.convert(der).toString());

/// The only door to the bank's servers. Adds auth, request ids, retries for safe reads,
/// maps every failure to an [ApiException], and logs without secrets.
class ApiClient {
  ApiClient({
    required ApiConfig config,
    required this._tokens,
    this.onSessionExpired,
    this.onMaintenance,
    this._log,
    HttpClientAdapter? adapter,
    Dio? dio,
    this.retryDelay = const Duration(milliseconds: 400),
  }) : dio = dio ?? Dio() {
    this.dio.options
      ..baseUrl = config.baseUrl
      ..connectTimeout = config.connectTimeout
      ..receiveTimeout = config.receiveTimeout
      ..sendTimeout = config.receiveTimeout
      ..headers = {'Accept': 'application/json'}
      ..validateStatus = (s) => s != null && s >= 200 && s < 300;
    this.dio.httpClientAdapter = adapter ?? _adapterFor(config);
    this.dio.interceptors.add(_Interceptor(this));
  }

  final Dio dio;
  final TokenAuthority _tokens;
  final void Function(String line)? _log;
  final Duration retryDelay;

  /// Called once the access token is rejected and cannot be refreshed.
  final void Function()? onSessionExpired;

  /// Called when the server reports maintenance; the app shows a full-screen notice.
  final void Function(MaintenanceException e)? onMaintenance;

  static HttpClientAdapter _adapterFor(ApiConfig config) {
    if (kIsWeb || config.certificatePins.isEmpty) return IOHttpClientAdapter();
    return IOHttpClientAdapter(
      validateCertificate: (cert, host, port) => cert != null && certificateMatchesPins(cert.der, config.certificatePins),
    );
  }

  /// A Dio for token refresh calls: same server and timeouts, but no auth interceptor.
  static Dio bare(ApiConfig config) => Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ),
  )..httpClientAdapter = _adapterFor(config);

  Future<Json> get(String path, {Map<String, Object?>? query, bool authenticated = true}) =>
      _send('GET', path, query: query, authenticated: authenticated);

  /// [idempotencyKey] must be reused when the same operation is resent after an ambiguous failure.
  Future<Json> post(String path, {Object? body, String? idempotencyKey, bool authenticated = true}) =>
      _send('POST', path, body: body, idempotencyKey: idempotencyKey, authenticated: authenticated);

  Future<Json> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<Json> delete(String path) => _send('DELETE', path);

  Future<Json> _send(String method, String path, {Object? body, Map<String, Object?>? query, String? idempotencyKey, bool authenticated = true}) async {
    try {
      final res = await dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'Idempotency-Key': ?idempotencyKey},
          extra: {'auth': authenticated},
        ),
      );
      final data = res.data;
      if (data == null || (data is String && data.isEmpty)) return const {};
      if (data is Json) return data;
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Json) return decoded;
      }
      throw const ServerException('The bank sent a response we couldn’t read.');
    } on DioException catch (e) {
      final mapped = e.error;
      throw mapped is ApiException ? mapped : _map(e);
    } on FormatException {
      throw const ServerException('The bank sent a response we couldn’t read.');
    }
  }

  ApiException _map(DioException e) {
    final id = e.requestOptions.headers['X-Request-Id'] as String?;
    final res = e.response;
    if (res == null) return NetworkException(const NetworkException().message, id);
    final status = res.statusCode ?? 0;
    final body = res.data is Json ? res.data as Json : const <String, dynamic>{};
    final code = body['code'] is String ? body['code'] as String : 'error';
    final message = body['message'] is String ? body['message'] as String : null;
    if (status == 401) return UnauthorizedException(const UnauthorizedException().message, id);
    if (status == 503 && (code == 'maintenance' || res.headers.value('x-maintenance') != null)) {
      final secs = int.tryParse(res.headers.value('retry-after') ?? '');
      return MaintenanceException(message ?? const MaintenanceException().message, secs == null ? null : Duration(seconds: secs), id);
    }
    if (status >= 500) return ServerException(const ServerException().message, status, id);
    final fields = body['fields'];
    return RejectedException(
      message ?? 'The bank couldn’t complete that request.',
      code: code,
      statusCode: status,
      requestId: id,
      fieldErrors: fields is Map ? {for (final f in fields.entries) '${f.key}': '${f.value}'} : const {},
    );
  }
}

class _Interceptor extends Interceptor {
  _Interceptor(this.client);
  final ApiClient client;

  static const _maxRetries = 2;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Request-Id'] ??= _randomId();
    final token = client._tokens.accessToken;
    if (options.extra['auth'] != false && token != null) options.headers['Authorization'] = 'Bearer $token';
    client._logRequest(options);
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    client._logResponse(response.requestOptions, response.statusCode, response.data);
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    final status = err.response?.statusCode;
    client._logResponse(req, status, err.response?.data, error: err.type.name);

    // 401: renew once, then replay the original request.
    if (status == 401 && req.extra['auth'] != false && req.extra['retriedAuth'] != true) {
      if (await client._tokens.refresh()) {
        req.extra['retriedAuth'] = true;
        req.headers.remove('Authorization');
        try {
          return handler.resolve(await client.dio.fetch<dynamic>(req));
        } on DioException catch (e) {
          return handler.reject(e);
        }
      }
      client._tokens.clear();
      client.onSessionExpired?.call();
    }

    // Reads are safe to repeat; writes are not (a payment may have gone through before the connection dropped).
    final mapped = client._map(err);
    final transient = switch (mapped) {
      NetworkException() => err.type != DioExceptionType.cancel && err.type != DioExceptionType.badCertificate,
      ServerException() => const [502, 503, 504].contains(status),
      _ => false,
    };
    final tries = (req.extra['tries'] as int?) ?? 0;
    if (req.method == 'GET' && transient && tries < _maxRetries) {
      req.extra['tries'] = tries + 1;
      await Future<void>.delayed(client.retryDelay * (tries + 1));
      try {
        return handler.resolve(await client.dio.fetch<dynamic>(req));
      } on DioException catch (e) {
        return handler.reject(e);
      }
    }

    if (mapped is MaintenanceException) client.onMaintenance?.call(mapped);
    handler.reject(DioException(requestOptions: req, response: err.response, type: err.type, error: mapped));
  }
}

extension on ApiClient {
  void _logRequest(RequestOptions o) {
    final log = _log;
    if (log == null) return;
    log('→ ${o.method} ${LogSanitizer.uri(o.uri)} ${LogSanitizer.headers(o.headers)} ${LogSanitizer.body(o.data) ?? ''}');
  }

  void _logResponse(RequestOptions o, int? status, Object? data, {String? error}) {
    final log = _log;
    if (log == null) return;
    log('← ${status ?? error} ${o.method} ${LogSanitizer.uri(o.uri)} ${LogSanitizer.body(data) ?? ''}');
  }
}

/// `GET /v1/health`: unauthenticated, 200 when the bank is serving requests.
class ApiHealthCheck implements HealthCheck {
  ApiHealthCheck(this._api);
  final ApiClient _api;

  @override
  Future<bool> isUp() async {
    try {
      await _api.get('/v1/health', authenticated: false);
      return true;
    } on ApiException {
      return false;
    }
  }
}
