import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/mappers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../../../shared/models/service_models.dart';
import '../../savings/domain/phase5_repositories.dart';
import '../domain/banking_repositories.dart';

class ApiAccountRepository implements AccountRepository {
  ApiAccountRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<BankAccount>> accounts() async => items(await _api.get('/v1/accounts')).map(accountFromJson).toList();

  @override
  Future<BankAccount> open({required AccountType type, required String name, required String fromAccountId, required double amount}) async {
    try {
      final json = await _api.post(
        '/v1/accounts',
        idempotencyKey: newIdempotencyKey(),
        body: {
          'type': type.name,
          'name': name,
          'fromAccountId': fromAccountId,
          'amountMinor': toMinor(amount),
        },
      );
      return accountFromJson(json);
    } on RejectedException catch (e) {
      throw PaymentException(paymentFailureFor(e.code), e.message);
    }
  }
}

class ApiCardRepository implements CardRepository {
  ApiCardRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<BankCard>> cards() async => items(await _api.get('/v1/cards')).map(cardFromJson).toList();

  String _path(String id, String leaf) => '/v1/cards/${Uri.encodeComponent(id)}/$leaf';

  /// Business refusals (4xx) become [CardException] so the UI can show the bank's own wording.
  Future<T> _card<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on RejectedException catch (e) {
      throw CardException(e.message);
    }
  }

  @override
  Future<void> setFrozen(String cardId, bool frozen) => _card(() => _api.put(_path(cardId, 'freeze'), body: {'frozen': frozen}));

  @override
  Future<CardControls> controls(String cardId) async => cardControlsFromJson(await _api.get(_path(cardId, 'controls')));

  @override
  Future<void> updateControls(String cardId, CardControls controls) =>
      _card(() => _api.put(_path(cardId, 'controls'), body: cardControlsToJson(controls)));

  /// Sent over TLS and verified by the issuer; the app never stores or logs a card PIN.
  @override
  Future<void> changePin(String cardId, {required String currentPin, required String newPin}) =>
      _card(() => _api.put(_path(cardId, 'pin'), body: {'currentPin': currentPin, 'newPin': newPin}));

  @override
  Future<BankCard> requestCard({required CardKind kind, required String accountId, required String holder, String? collectionBranch}) => _card(
    () async => cardFromJson(
      await _api.post('/v1/cards', body: {'kind': kind.name, 'accountId': accountId, 'collectionBranch': collectionBranch}, idempotencyKey: newIdempotencyKey()),
    ),
  );

  @override
  Future<void> activateCard(String cardId) => _card(() => _api.post(_path(cardId, 'activate')));

  @override
  Future<void> reportLostOrStolen(String cardId) => _card(() => _api.post(_path(cardId, 'report-lost')));
}

class ApiLoanRepository implements LoanRepository {
  ApiLoanRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Loan>> loans() async => items(await _api.get('/v1/loans')).map(loanFromJson).toList();

  @override
  Future<List<LoanApplication>> applications() async => items(await _api.get('/v1/loan-applications')).map(loanApplicationFromJson).toList();

  @override
  Future<LoanApplication> apply(LoanApplicationRequest r) async {
    try {
      return loanApplicationFromJson(
        await _api.post(
          '/v1/loan-applications',
          idempotencyKey: newIdempotencyKey(),
          body: {
            'type': r.type.name,
            'amountMinor': toMinor(r.amount),
            'termMonths': r.termMonths,
            'monthlyIncomeMinor': toMinor(r.monthlyIncome),
            'employment': r.employment,
            'purpose': r.purpose,
          },
        ),
      );
    } on RejectedException catch (e) {
      throw LoanApplicationException(e.message);
    }
  }
}

class ApiTransactionRepository implements TransactionRepository {
  ApiTransactionRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Transaction>> transactions() async {
    final list = items(await _api.get('/v1/transactions', query: {'limit': 500})).map(transactionFromJson).toList();
    return list..sort((a, b) => b.date.compareTo(a.date));
  }

  /// The contract does not expose original payment instructions, so repeating is unavailable.
  @override
  Future<PaymentDraft?> repeatDraft(String transactionId) async => null;
}
