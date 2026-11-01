import '../../../shared/models/engagement_models.dart';

abstract interface class NotificationRepository {
  Future<List<AppNotification>> notifications();
  Future<void> add(AppNotification notification);
  Future<void> markRead(String id);
  Future<void> markAllRead();
}

abstract interface class SecurityRepository {
  Future<List<DeviceSession>> sessions();

  /// Signs a device out. The current device can't be revoked here — use log out.
  Future<void> revoke(String sessionId);
  Future<void> revokeOthers();
  Future<List<LoginEvent>> loginHistory();
  Future<void> recordSignIn({required bool success});
  Future<bool> twoFactorEnabled();
  Future<void> setTwoFactor(bool enabled);
}

abstract interface class LimitsRepository {
  Future<TransferLimits> limits();

  /// Throws `PaymentException` if [daily] is outside 0 … the bank maximum.
  Future<void> setDaily(double daily);
}

abstract interface class SupportRepository {
  Future<List<SupportBranch>> nearby();
}

/// Opens phone, mail and map links. Behind an interface so tests don't launch anything.
abstract interface class LinkLauncher {
  /// Returns false when nothing on the device can handle [uri].
  Future<bool> open(Uri uri);
}
