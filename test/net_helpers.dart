import 'dart:convert';
import 'dart:typed_data';
import 'package:bank_app/core/network/api_client.dart';
import 'package:bank_app/core/network/api_config.dart';
import 'package:bank_app/core/network/api_exceptions.dart';
import 'package:bank_app/core/network/token_authority.dart';
import 'package:bank_app/core/security/secure_store.dart';
import 'package:bank_app/core/security/session_store.dart';
import 'package:dio/dio.dart';

typedef Handler = ResponseBody Function(RequestOptions o);

ResponseBody json(Object body, [int status = 200, Map<String, List<String>> headers = const {}]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

/// Stands in for the network: records every request and answers with whatever [handler] returns.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  Handler handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}

  int count(String path) => requests.where((r) => r.path == path).length;
}

class Rig {
  Rig(Handler handler) : adapter = FakeAdapter(handler) {
    store = MemorySecureStore();
    sessions = SessionStore(store);
    final bare = Dio(BaseOptions(baseUrl: 'https://api.test', validateStatus: (s) => s != null && s >= 200 && s < 300))..httpClientAdapter = adapter;
    tokens = SessionTokenAuthority(sessions, bare);
    client = ApiClient(
      config: ApiConfig(baseUrl: 'https://api.test'),
      tokens: tokens,
      adapter: adapter,
      retryDelay: Duration.zero,
      onSessionExpired: () => expired++,
      onMaintenance: maintenance.add,
      log: logs.add,
    );
  }
  final FakeAdapter adapter;
  late final MemorySecureStore store;
  late final SessionStore sessions;
  late final SessionTokenAuthority tokens;
  late final ApiClient client;
  int expired = 0;
  final maintenance = <MaintenanceException>[];
  final logs = <String>[];
}

