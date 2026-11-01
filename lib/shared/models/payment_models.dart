import 'package:flutter/foundation.dart';
import 'models.dart';

enum PaymentKind { transfer, bill, qr, loan }

/// How often a scheduled payment repeats.
enum Recurrence { once, weekly, monthly }

enum ScheduleStatus { active, completed, cancelled, failed }

@immutable
class Beneficiary {
  const Beneficiary({
    required this.id,
    required this.bank,
    required this.accountNumber,
    required this.name,
    this.nickname = '',
    this.favorite = false,
  });
  final String id, bank, accountNumber, name, nickname;
  final bool favorite;

  String get displayName => nickname.isEmpty ? name : nickname;
  String get masked => accountNumber.length <= 4 ? accountNumber : '•••• ${accountNumber.substring(accountNumber.length - 4)}';

  Beneficiary copyWith({String? nickname, bool? favorite}) => Beneficiary(
    id: id,
    bank: bank,
    accountNumber: accountNumber,
    name: name,
    nickname: nickname ?? this.nickname,
    favorite: favorite ?? this.favorite,
  );
}

/// A payment the user has composed but not yet authorised. Every payment type
/// (transfer, bill, QR, loan) is reduced to this before review.
@immutable
class PaymentDraft {
  const PaymentDraft({
    required this.kind,
    required this.fromAccountId,
    required this.payee,
    required this.payeeDetail,
    required this.amount,
    this.fee = 0,
    this.reference = '',
    this.details = const [],
    this.toAccountId,
    this.category = TxCategory.transfer,
    this.beneficiaryToSave,
    this.scheduledFor,
    this.loanId,
    this.recurrence = Recurrence.once,
  });
  final PaymentKind kind;
  final String fromAccountId;

  /// Name shown as the recipient, and a secondary line (bank, provider, masked number…).
  final String payee, payeeDetail;
  final double amount, fee;
  final String reference;

  /// Extra label/value rows shown on review and the receipt.
  final List<(String, String)> details;

  /// Set for transfers between the customer's own accounts.
  final String? toAccountId;
  final TxCategory category;
  final Beneficiary? beneficiaryToSave;
  final DateTime? scheduledFor;

  /// Set for loan instalments: which loan the money is applied to.
  final String? loanId;

  /// Only meaningful when [scheduledFor] is set.
  final Recurrence recurrence;

  double get total => amount + fee;
  bool get isScheduled => scheduledFor != null && scheduledFor!.isAfter(DateTime.now().add(const Duration(minutes: 1)));

  PaymentDraft withAccount(String id) => PaymentDraft(
    kind: kind,
    fromAccountId: id,
    payee: payee,
    payeeDetail: payeeDetail,
    amount: amount,
    fee: fee,
    reference: reference,
    details: details,
    toAccountId: toAccountId,
    category: category,
    beneficiaryToSave: beneficiaryToSave,
    scheduledFor: scheduledFor,
    loanId: loanId,
    recurrence: recurrence,
  );

  /// The same payment with a new date (used to queue the next run of a repeating payment).
  PaymentDraft scheduledAt(DateTime when) => PaymentDraft(
    kind: kind,
    fromAccountId: fromAccountId,
    payee: payee,
    payeeDetail: payeeDetail,
    amount: amount,
    fee: fee,
    reference: reference,
    details: details,
    toAccountId: toAccountId,
    category: category,
    beneficiaryToSave: beneficiaryToSave,
    scheduledFor: when,
    loanId: loanId,
    recurrence: recurrence,
  );

  /// The same payment, to be made now.
  PaymentDraft asImmediate() => PaymentDraft(
    kind: kind,
    fromAccountId: fromAccountId,
    payee: payee,
    payeeDetail: payeeDetail,
    amount: amount,
    fee: fee,
    reference: reference,
    details: details,
    toAccountId: toAccountId,
    category: category,
    beneficiaryToSave: beneficiaryToSave,
    loanId: loanId,
  );
}

/// A payment waiting for its date, once or repeating. Seen by the customer on the Scheduled payments screen.
@immutable
class ScheduledPayment {
  const ScheduledPayment({
    required this.id,
    required this.kind,
    required this.fromAccountId,
    required this.payee,
    required this.payeeDetail,
    required this.amount,
    required this.nextRun,
    this.fee = 0,
    this.reference = '',
    this.recurrence = Recurrence.once,
    this.status = ScheduleStatus.active,
    this.runCount = 0,
    this.lastMessage,
  });
  final String id, fromAccountId, payee, payeeDetail, reference;
  final PaymentKind kind;
  final double amount, fee;
  final DateTime nextRun;
  final Recurrence recurrence;
  final ScheduleStatus status;

  /// How many times it has been paid so far.
  final int runCount;

  /// Why the most recent run failed, if it did.
  final String? lastMessage;

  bool get active => status == ScheduleStatus.active;

  ScheduledPayment copyWith({DateTime? nextRun, ScheduleStatus? status, int? runCount, String? lastMessage, bool clearMessage = false}) => ScheduledPayment(
    id: id,
    kind: kind,
    fromAccountId: fromAccountId,
    payee: payee,
    payeeDetail: payeeDetail,
    amount: amount,
    fee: fee,
    reference: reference,
    nextRun: nextRun ?? this.nextRun,
    recurrence: recurrence,
    status: status ?? this.status,
    runCount: runCount ?? this.runCount,
    lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
  );
}

@immutable
class Receipt {
  const Receipt({
    required this.id,
    required this.kind,
    required this.status,
    required this.payee,
    required this.amount,
    required this.fee,
    required this.fromName,
    required this.fromMasked,
    required this.reference,
    required this.date,
    required this.details,
    this.scheduled = false,
  });
  final String id, payee, fromName, fromMasked, reference;
  final PaymentKind kind;
  final TxStatus status;
  final double amount, fee;
  final DateTime date;
  final List<(String, String)> details;
  final bool scheduled;

  double get total => amount + fee;
}

enum PaymentFailure { insufficientFunds, invalidRecipient, limitExceeded, unavailable }

class PaymentException implements Exception {
  const PaymentException(this.failure, this.message);
  final PaymentFailure failure;
  final String message;
  @override
  String toString() => message;
}
