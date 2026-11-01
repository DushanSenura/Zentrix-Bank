import 'package:url_launcher/url_launcher.dart';
import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/payment_models.dart';
import '../../payments/data/mock_ledger.dart';
import '../domain/engagement_repositories.dart';

class MockNotificationRepository implements NotificationRepository {
  /// A new customer's inbox: a single welcome note.
  MockNotificationRepository.welcome(String firstName, {DateTime? now}) : _now = now ?? DateTime.now() {
    _items.add(
      AppNotification(
        id: 'welcome',
        category: NotifCategory.bankNotices,
        title: 'Welcome to Zentrix Bank${firstName.isEmpty ? '' : ', $firstName'}',
        body: 'Your account is open. Add a transaction PIN in Security, then try a transfer or set a savings goal.',
        date: _now,
      ),
    );
  }

  MockNotificationRepository({DateTime? now}) : _now = now ?? DateTime.now() {
    AppNotification n(String id, NotifCategory c, String title, String body, Duration ago, {bool read = false, Severity s = Severity.info}) =>
        AppNotification(id: id, category: c, title: title, body: body, date: _now.subtract(ago), read: read, severity: s);
    _items.addAll([
      n('n1', NotifCategory.transactions, 'Card payment', 'LKR 2,500.00 was spent using your card ending 4821.', const Duration(hours: 2)),
      n('n2', NotifCategory.security, 'New device signed in', 'A new device signed into your account near Colombo.', const Duration(hours: 5), s: Severity.warning),
      n('n3', NotifCategory.payments, 'Bill payment successful', 'Your electricity bill payment of LKR 6,840.00 was successful.', const Duration(days: 1), read: true),
      n('n4', NotifCategory.offers, 'Weekend dining offer', '15% back at partner restaurants this weekend. Terms apply.', const Duration(days: 2)),
      n('n5', NotifCategory.bankNotices, 'Scheduled maintenance', 'Online banking will be unavailable on Sunday 2:00–3:00 AM.', const Duration(days: 3), read: true),
      n('n6', NotifCategory.security, 'Large transfer', 'A transfer of LKR 20,000.00 was made from your Savings Account.', const Duration(days: 19), read: true, s: Severity.info),
      n('n7', NotifCategory.security, 'Password changed', 'Your password was changed. If this wasn’t you, contact us immediately.', const Duration(days: 40), read: true, s: Severity.critical),
    ]);
  }
  final DateTime _now;
  final _items = <AppNotification>[];

  @override
  Future<List<AppNotification>> notifications() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return ([..._items]..sort((a, b) => b.date.compareTo(a.date)));
  }

  @override
  Future<void> add(AppNotification n) async => _items.insert(0, n);

  @override
  Future<void> markRead(String id) async {
    final i = _items.indexWhere((n) => n.id == id);
    if (i >= 0) _items[i] = _items[i].copyWith(read: true);
  }

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(read: true);
    }
  }
}

class MockSecurityRepository implements SecurityRepository {
  /// A new customer has only the device they registered on and no past sign-ins.
  MockSecurityRepository.fresh({DateTime? now}) : _now = now ?? DateTime.now() {
    _sessions.add(DeviceSession(id: 'd-this', name: 'This device', platform: 'Mobile app', lastActive: _now, approxLocation: 'Colombo, LK', current: true));
  }

  MockSecurityRepository({DateTime? now}) : _now = now ?? DateTime.now() {
    _sessions.addAll([
      DeviceSession(id: 'd-this', name: 'This device', platform: 'Mobile app', lastActive: _now, approxLocation: 'Colombo, LK', current: true),
      DeviceSession(id: 'd-2', name: 'Pixel 8', platform: 'Android', lastActive: _now.subtract(const Duration(hours: 5)), approxLocation: 'Colombo, LK'),
      DeviceSession(id: 'd-3', name: 'iPad', platform: 'iPadOS', lastActive: _now.subtract(const Duration(days: 9)), approxLocation: 'Kandy, LK'),
    ]);
    _history.addAll([
      LoginEvent(date: _now.subtract(const Duration(hours: 5)), device: 'Pixel 8', success: true, approxLocation: 'Colombo, LK'),
      LoginEvent(date: _now.subtract(const Duration(days: 2)), device: 'Unknown browser', success: false, approxLocation: 'Singapore'),
      LoginEvent(date: _now.subtract(const Duration(days: 9)), device: 'iPad', success: true, approxLocation: 'Kandy, LK'),
    ]);
  }
  final DateTime _now;
  final _sessions = <DeviceSession>[];
  final _history = <LoginEvent>[];
  bool _twoFactor = false;

  @override
  Future<List<DeviceSession>> sessions() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_sessions);
  }

  @override
  Future<void> revoke(String sessionId) async => _sessions.removeWhere((s) => s.id == sessionId && !s.current);

  @override
  Future<void> revokeOthers() async => _sessions.removeWhere((s) => !s.current);

  @override
  Future<List<LoginEvent>> loginHistory() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_history);
  }

  @override
  Future<void> recordSignIn({required bool success}) async =>
      _history.insert(0, LoginEvent(date: DateTime.now(), device: 'This device', success: success, approxLocation: 'Colombo, LK'));

  @override
  Future<bool> twoFactorEnabled() async => _twoFactor;

  @override
  Future<void> setTwoFactor(bool enabled) async => _twoFactor = enabled;
}

class MockLimitsRepository implements LimitsRepository {
  MockLimitsRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<TransferLimits> limits() async => TransferLimits(bankMaximum: MockLedger.dailyTransferLimit, daily: _ledger.userDailyLimit);

  @override
  Future<void> setDaily(double daily) async {
    if (daily < 0 || daily > MockLedger.dailyTransferLimit) {
      throw const PaymentException(PaymentFailure.limitExceeded, 'Your limit can’t be above the bank’s maximum.');
    }
    _ledger.userDailyLimit = daily;
  }
}

class MockSupportRepository implements SupportRepository {
  @override
  Future<List<SupportBranch>> nearby() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const [
      SupportBranch(name: 'Zentrix Bank — Colombo Fort', address: '12 Chatham Street, Colombo 01', distanceKm: 1.2, isAtm: false, latitude: 6.9344, longitude: 79.8428),
      SupportBranch(name: 'ATM — Liberty Plaza', address: 'R. A. De Mel Mawatha, Colombo 03', distanceKm: 2.4, isAtm: true, latitude: 6.9100, longitude: 79.8520),
      SupportBranch(name: 'Zentrix Bank — Bambalapitiya', address: '314 Galle Road, Colombo 04', distanceKm: 4.1, isAtm: false, latitude: 6.8905, longitude: 79.8560),
      SupportBranch(name: 'ATM — Arcade Independence Square', address: 'Independence Ave, Colombo 07', distanceKm: 5.0, isAtm: true, latitude: 6.9000, longitude: 79.8650),
    ];
  }
}

class UrlLinkLauncher implements LinkLauncher {
  const UrlLinkLauncher();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }
}
