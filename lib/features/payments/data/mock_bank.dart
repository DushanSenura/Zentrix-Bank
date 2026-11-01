import '../../../shared/models/models.dart';
import '../../authentication/data/mock_auth_repository.dart';
import '../../dashboard/data/mock_banking_repositories.dart';
import '../../security/data/mock_engagement_repositories.dart';
import 'mock_ledger.dart';

/// Everything the prototype's "bank" holds about one customer.
class MockCustomerData {
  MockCustomerData({
    required this.ledger,
    required this.cards,
    required this.beneficiaries,
    required this.notifications,
    required this.security,
  });
  final MockLedger ledger;
  final MockCardRepository cards;
  final MockBeneficiaryRepository beneficiaries;
  final MockNotificationRepository notifications;
  final MockSecurityRepository security;

  /// Told when the mock bank puts something new in the inbox on its own (a card became ready), so the screen can refresh.
  void Function()? onInboxChanged;

  /// The sample customer: accounts, cards, history, beneficiaries and alerts to explore.
  factory MockCustomerData.demo() {
    final inbox = MockNotificationRepository();
    late final MockCustomerData data;
    data = MockCustomerData(
      ledger: MockLedger(),
      cards: MockCardRepository(notify: (n) {
        inbox.add(n);
        data.onInboxChanged?.call();
      }),
      beneficiaries: MockBeneficiaryRepository(),
      notifications: inbox,
      security: MockSecurityRepository(),
    );
    return data;
  }

  /// A customer who has just opened an account: one account holding the opening deposit and nothing else.
  /// No cards, beneficiaries, goals, loans or history have been invented for them.
  factory MockCustomerData.newCustomer(AppUser user, {required double openingDeposit, AccountType accountType = AccountType.savings}) {
    final digits = user.customerNumber.replaceAll(RegExp(r'\D'), '');
    final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : digits.padLeft(4, '0');
    final inbox = MockNotificationRepository.welcome(user.firstName);
    late final MockCustomerData data;
    data = MockCustomerData(
      ledger: MockLedger.fresh(openingDeposit: openingDeposit, accountLast4: last4, accountType: accountType),
      cards: MockCardRepository(cards: const [], notify: (n) {
        inbox.add(n);
        data.onInboxChanged?.call();
      }),
      beneficiaries: MockBeneficiaryRepository(seed: const []),
      notifications: inbox,
      security: MockSecurityRepository.fresh(),
    );
    return data;
  }
}

/// The prototype's core bank: one independent [MockCustomerData] per customer, kept for the life of the app run.
/// A customer who signs out and back in sees their own changes; a different customer never sees them.
class MockBank {
  final _customers = <String, MockCustomerData>{};
  final _openings = <String, ({double deposit, AccountType type})>{};

  /// Called when registration succeeds, so the new customer's account opens with what they deposited.
  void openAccount(AppUser user, {required double deposit, AccountType type = AccountType.savings}) {
    _openings[user.id] = (deposit: deposit, type: type);
    _customers.remove(user.id);
  }

  MockCustomerData forUser(AppUser? user) {
    if (user == null) return _signedOut ??= MockCustomerData.newCustomer(_nobody, openingDeposit: 0);
    return _customers.putIfAbsent(user.id, () {
      if (user.id == MockAuthRepository.demoUserId) return MockCustomerData.demo();
      final opening = _openings[user.id];
      return MockCustomerData.newCustomer(user, openingDeposit: opening?.deposit ?? 0, accountType: opening?.type ?? AccountType.savings);
    });
  }

  MockCustomerData? _signedOut;
  static const _nobody = AppUser(id: '', fullName: '', firstName: '', customerNumber: '', email: '', phone: '');
}
