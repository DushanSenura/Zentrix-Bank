import '../../../shared/models/engagement_models.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../../payments/data/mock_ledger.dart';
import '../domain/banking_repositories.dart';

const _latency = Duration(milliseconds: 650);

class MockAccountRepository implements AccountRepository {
  MockAccountRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<List<BankAccount>> accounts() async {
    await Future<void>.delayed(_latency);
    _ledger.runDue();
    return List.unmodifiable(_ledger.accounts);
  }

  @override
  Future<BankAccount> open({required AccountType type, required String name, required String fromAccountId, required double amount}) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _ledger.openAccount(type: type, name: name, fromAccountId: fromAccountId, amount: amount);
  }
}

class MockCardRepository implements CardRepository {
  /// [clock] and [notify] exist so tests can control time and see what the "bank" tells the customer.
  /// With no [notify], nobody is told anything.
  MockCardRepository({List<BankCard> cards = _demoCards, DateTime Function()? clock, this._notify}) : _cards = [...cards], _clock = clock ?? DateTime.now;

  /// Demo card PIN. A real issuer verifies this inside its HSM; it is never held on the device.
  static const demoCardPin = '4821';
  static const maxVirtualCards = 3;

  static const _demoCards = [
    BankCard(id: 'c-1', kind: CardKind.debit, network: CardNetwork.visa, holder: 'DUSHAN PERERA', last4: '4821', expiry: '09/28'),
    BankCard(id: 'c-2', kind: CardKind.credit, network: CardNetwork.mastercard, holder: 'DUSHAN PERERA', last4: '1176', expiry: '02/29'),
    BankCard(id: 'c-3', kind: CardKind.virtual, network: CardNetwork.visa, holder: 'DUSHAN PERERA', last4: '6630', expiry: '11/27'),
  ];

  final List<BankCard> _cards;
  final DateTime Function() _clock;
  final void Function(AppNotification)? _notify;
  final _frozen = <String>{};
  final _blocked = <String>{};
  final _controls = <String, CardControls>{};
  final _pins = <String, String>{};

  /// Cards the bank has not activated yet, and debit cards waiting to be collected (with their branch and ready day).
  final _pendingApproval = <String>{};
  final _collection = <String, ({DateTime readyOn, String branch})>{};
  final _readyAnnounced = <String>{};
  Duration _skew = Duration.zero;
  int _issued = 0;

  /// The mock bank's idea of "now": the real clock plus whatever the prototype tools have skipped.
  DateTime get now => _clock().add(_skew);

  BankCard _find(String id) => _cards.firstWhere((c) => c.id == id, orElse: () => throw const CardException('That card could not be found.'));

  void _requireUsable(String id, {String? action}) {
    final card = _find(id);
    if (_blocked.contains(id)) throw const CardException('This card has been blocked permanently.');
    if (_pendingApproval.contains(card.id) || _collection.containsKey(card.id)) {
      throw CardException('This card isn’t active yet${action == null ? '' : ', so you can’t $action it'}.');
    }
  }

  BankCard _view(BankCard c) => c.copyWith(
    frozen: _frozen.contains(c.id),
    blocked: _blocked.contains(c.id),
    issuance: _pendingApproval.contains(c.id)
        ? CardIssuance.pendingApproval
        : (_collection[c.id] == null
              ? CardIssuance.active
              : (now.isBefore(_collection[c.id]!.readyOn) ? CardIssuance.preparing : CardIssuance.readyToCollect)),
    readyOn: _collection[c.id]?.readyOn,
    collectionBranch: _collection[c.id]?.branch,
  );

  /// The bank tells the customer when a debit card has finished being made.
  void _announceReady() {
    for (final e in _collection.entries) {
      if (now.isBefore(e.value.readyOn) || !_readyAnnounced.add(e.key)) continue;
      final card = _find(e.key);
      _notify?.call(
        AppNotification(
          id: 'card-ready-${e.key}',
          category: NotifCategory.bankNotices,
          title: 'Your debit card is ready to collect',
          body: 'Your debit card ending ${card.last4} is ready. Please collect it from ${e.value.branch} and bring your ID. Once you have it, activate it in the app.',
          date: now,
        ),
      );
    }
  }

  @override
  Future<List<BankCard>> cards() async {
    await Future<void>.delayed(_latency);
    _announceReady();
    return [for (final c in _cards) _view(c)];
  }

  @override
  Future<void> setFrozen(String cardId, bool frozen) async {
    _requireUsable(cardId, action: 'freeze');
    frozen ? _frozen.add(cardId) : _frozen.remove(cardId);
  }

  @override
  Future<CardControls> controls(String cardId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final card = _find(cardId);
    return _controls[cardId] ??
        CardControls(
          dailyLimit: card.kind == CardKind.credit ? 150000 : 50000,
          maxDailyLimit: card.kind == CardKind.credit ? 300000 : 100000,
          onlineEnabled: true,
          internationalEnabled: false,
        );
  }

  @override
  Future<void> updateControls(String cardId, CardControls controls) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _requireUsable(cardId, action: 'change');
    if (controls.dailyLimit < 0 || controls.dailyLimit > controls.maxDailyLimit) {
      throw const CardException('That limit is above what the bank allows for this card.');
    }
    _controls[cardId] = controls;
  }

  @override
  Future<void> changePin(String cardId, {required String currentPin, required String newPin}) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _requireUsable(cardId, action: 'change the PIN of');
    if ((_pins[cardId] ?? demoCardPin) != currentPin) throw const CardException('The current card PIN is incorrect.');
    if (!RegExp(r'^\d{4}$').hasMatch(newPin)) throw const CardException('A card PIN must be exactly 4 digits.');
    _pins[cardId] = newPin;
  }

  @override
  Future<BankCard> requestCard({required CardKind kind, required String accountId, required String holder, String? collectionBranch}) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (kind == CardKind.credit) throw const CardException('Credit cards need an application. Please visit a branch.');
    final live = _cards.where((c) => c.kind == kind && !_blocked.contains(c.id)).length;
    if (kind == CardKind.virtual && live >= maxVirtualCards) {
      throw const CardException('You already have the maximum of 3 virtual cards. Block one to create another.');
    }
    if (kind == CardKind.debit) {
      if (collectionBranch == null || collectionBranch.trim().isEmpty) throw const CardException('Choose the branch where you’ll collect your card.');
      if (_collection.isNotEmpty) throw const CardException('A debit card is already being prepared for you. Collect and activate it before ordering another.');
    }
    _issued++;
    final at = now;
    final last4 = (4000 + (at.millisecondsSinceEpoch + _issued * 7919) % 5999).toString().padLeft(4, '0');
    final card = BankCard(
      id: 'c-new-$_issued',
      kind: kind,
      network: CardNetwork.visa,
      holder: holder.toUpperCase(),
      last4: last4,
      expiry: '${at.month.toString().padLeft(2, '0')}/${((at.year + 4) % 100).toString().padLeft(2, '0')}',
    );
    _cards.add(card);
    if (kind == CardKind.virtual) {
      _pendingApproval.add(card.id);
    } else {
      _collection[card.id] = (readyOn: at.add(const Duration(days: debitCardPreparationDays)), branch: collectionBranch!.trim());
    }
    return _view(card);
  }

  @override
  Future<void> activateCard(String cardId) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _find(cardId);
    if (_pendingApproval.contains(cardId)) {
      throw const CardException('The bank activates virtual cards. We’ll tell you as soon as yours is approved.');
    }
    final waiting = _collection[cardId];
    if (waiting == null) throw const CardException('This card is already active.');
    if (now.isBefore(waiting.readyOn)) {
      throw const CardException('This card isn’t ready to collect yet. We’ll tell you when it is.');
    }
    _collection.remove(cardId);
    _readyAnnounced.remove(cardId);
  }

  @override
  Future<void> reportLostOrStolen(String cardId) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _find(cardId);
    if (_pendingApproval.contains(cardId) || _collection.containsKey(cardId)) {
      throw const CardException('This card isn’t active yet, so there’s nothing to block.');
    }
    _frozen.remove(cardId);
    _blocked.add(cardId);
  }

  // ---- The bank's side. Prototype only: in a real deployment bank staff do these in their own systems. ----------

  /// An administrator approves and activates every virtual card waiting for it. Returns how many were activated.
  int approvePendingVirtualCards() {
    final ids = [..._pendingApproval];
    for (final id in ids) {
      _pendingApproval.remove(id);
      final card = _find(id);
      _notify?.call(
        AppNotification(
          id: 'card-approved-$id',
          category: NotifCategory.bankNotices,
          title: 'Your virtual card is active',
          body: 'The bank has approved your virtual card ending ${card.last4}. You can use it now.',
          date: now,
        ),
      );
    }
    return ids.length;
  }

  /// Moves the bank's clock forward, so a debit card being prepared reaches its collection day.
  void skipDays(int days) {
    _skew += Duration(days: days);
  }
}

class MockTransactionRepository implements TransactionRepository {
  MockTransactionRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<List<Transaction>> transactions() async {
    await Future<void>.delayed(_latency);
    _ledger.runDue();
    return List.unmodifiable(_ledger.transactions);
  }

  @override
  Future<PaymentDraft?> repeatDraft(String transactionId) async => _ledger.repeatDrafts[transactionId];
}
