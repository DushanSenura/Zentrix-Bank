import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/mappers.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/payment_models.dart';
import '../domain/engagement_repositories.dart';

String _id(String id) => Uri.encodeComponent(id);

class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<AppNotification>> notifications() async => items(await _api.get('/v1/notifications')).map(notificationFromJson).toList();

  /// For events the app itself observed (e.g. a card freeze). A server that records its own
  /// notifications may answer 204 and ignore the body.
  @override
  Future<void> add(AppNotification n) async {
    await _api.post('/v1/notifications', body: notificationToJson(n));
  }

  @override
  Future<void> markRead(String id) async {
    await _api.post('/v1/notifications/${_id(id)}/read');
  }

  @override
  Future<void> markAllRead() async {
    await _api.post('/v1/notifications/read-all');
  }
}

class ApiSecurityRepository implements SecurityRepository {
  ApiSecurityRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<DeviceSession>> sessions() async => items(await _api.get('/v1/security/sessions')).map(sessionFromJson).toList();

  @override
  Future<void> revoke(String sessionId) async {
    await _api.delete('/v1/security/sessions/${_id(sessionId)}');
  }

  @override
  Future<void> revokeOthers() async {
    await _api.post('/v1/security/sessions/revoke-others');
  }

  @override
  Future<List<LoginEvent>> loginHistory() async => items(await _api.get('/v1/security/login-history')).map(loginEventFromJson).toList();

  /// The server records every sign-in attempt itself; nothing to send from the device.
  @override
  Future<void> recordSignIn({required bool success}) async {}

  @override
  Future<bool> twoFactorEnabled() async => (await _api.get('/v1/security/two-factor'))['enabled'] == true;

  @override
  Future<void> setTwoFactor(bool enabled) async {
    await _api.put('/v1/security/two-factor', body: {'enabled': enabled});
  }
}

class ApiLimitsRepository implements LimitsRepository {
  ApiLimitsRepository(this._api);
  final ApiClient _api;

  @override
  Future<TransferLimits> limits() async => transferLimitsFromJson(await _api.get('/v1/limits/transfer'));

  @override
  Future<void> setDaily(double daily) async {
    try {
      await _api.put('/v1/limits/transfer', body: {'dailyMinor': toMinor(daily)});
    } on RejectedException catch (e) {
      throw PaymentException(PaymentFailure.limitExceeded, e.message);
    }
  }
}

class ApiSupportRepository implements SupportRepository {
  ApiSupportRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<SupportBranch>> nearby() async => items(await _api.get('/v1/support/branches')).map(branchFromJson).toList();
}
