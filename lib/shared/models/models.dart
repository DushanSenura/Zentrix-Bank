import 'package:flutter/foundation.dart';

/// Immutable domain models. Money is a `double` in these mock models;
/// a real backend integration should use integer minor units.

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.firstName,
    required this.customerNumber,
    required this.email,
    required this.phone,
  });
  final String id, fullName, firstName, customerNumber, email, phone;
}

enum AccountType { savings, current, fixedDeposit, foreignCurrency }

@immutable
class BankAccount {
  const BankAccount({
    required this.id,
    required this.type,
    required this.name,
    required this.maskedNumber,
    required this.balance,
    this.currency = 'LKR',
    this.active = true,
    this.interestRate,
    this.maturityDate,
  });
  final String id, name, maskedNumber, currency;
  final AccountType type;
  final double balance;
  final bool active;

  /// Annual interest, as a percentage, for deposits that pay it.
  final double? interestRate;

  /// When a fixed deposit pays out.
  final DateTime? maturityDate;

  BankAccount copyWith({double? balance}) => BankAccount(
    id: id,
    type: type,
    name: name,
    maskedNumber: maskedNumber,
    balance: balance ?? this.balance,
    currency: currency,
    active: active,
    interestRate: interestRate,
    maturityDate: maturityDate,
  );
}

enum CardKind { debit, credit, virtual }

enum CardNetwork { visa, mastercard }

/// Where a card is in its life, as decided by the bank (the app never works this out from its own clock).
///
/// Customers can't activate a virtual card themselves: the bank does, from its own system ([pendingApproval]).
/// A debit card is made by the bank ([preparing]) and then collected from a branch ([readyToCollect]).
enum CardIssuance { active, pendingApproval, preparing, readyToCollect }

/// How long the bank takes to prepare a debit card before it can be collected.
const debitCardPreparationDays = 5;

@immutable
class BankCard {
  const BankCard({
    required this.id,
    required this.kind,
    required this.network,
    required this.holder,
    required this.last4,
    required this.expiry,
    this.frozen = false,
    this.blocked = false,
    this.issuance = CardIssuance.active,
    this.readyOn,
    this.collectionBranch,
  });
  final String id, holder, last4, expiry;
  final CardKind kind;
  final CardNetwork network;

  /// Temporarily blocked by the customer; reversible.
  final bool frozen;

  /// Permanently blocked (reported lost or stolen). A replacement is issued; this card cannot be unblocked.
  final bool blocked;

  final CardIssuance issuance;

  /// For a debit card being made: the day it can be collected, and from which branch.
  final DateTime? readyOn;
  final String? collectionBranch;

  /// Whether the card can be used and managed. Until then it can only be waited for or, once ready, collected and activated.
  bool get usable => issuance == CardIssuance.active;

  BankCard copyWith({bool? frozen, bool? blocked, CardIssuance? issuance, DateTime? readyOn, String? collectionBranch}) => BankCard(
    id: id,
    kind: kind,
    network: network,
    holder: holder,
    last4: last4,
    expiry: expiry,
    frozen: frozen ?? this.frozen,
    blocked: blocked ?? this.blocked,
    issuance: issuance ?? this.issuance,
    readyOn: readyOn ?? this.readyOn,
    collectionBranch: collectionBranch ?? this.collectionBranch,
  );
}

/// Spending controls for one card. Limits are the customer's own; the bank sets [maxDailyLimit].
@immutable
class CardControls {
  const CardControls({required this.dailyLimit, required this.maxDailyLimit, this.onlineEnabled = true, this.internationalEnabled = false});
  final double dailyLimit, maxDailyLimit;
  final bool onlineEnabled, internationalEnabled;

  CardControls copyWith({double? dailyLimit, bool? onlineEnabled, bool? internationalEnabled}) => CardControls(
    dailyLimit: dailyLimit ?? this.dailyLimit,
    maxDailyLimit: maxDailyLimit,
    onlineEnabled: onlineEnabled ?? this.onlineEnabled,
    internationalEnabled: internationalEnabled ?? this.internationalEnabled,
  );
}

/// The bank refused a card change; [message] is safe to show.
class CardException implements Exception {
  const CardException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum TxCategory { food, shopping, transport, bills, entertainment, health, education, income, transfer, other }

enum TxStatus { completed, pending, failed }

@immutable
class Transaction {
  const Transaction({
    required this.id,
    required this.merchant,
    required this.category,
    required this.amount,
    required this.date,
    this.status = TxStatus.completed,
    this.accountId = 'a-sav',
    this.reference = '',
    this.method = '',
    this.internal = false,
  });
  final String id, merchant;
  final TxCategory category;

  /// Positive = money in, negative = money out.
  final double amount;
  final DateTime date;
  final TxStatus status;

  /// Account the money moved through.
  final String accountId;
  final String reference;

  /// How it was paid, e.g. "Debit card •••• 4821".
  final String method;

  /// Movement between the customer's own accounts or goals; excluded from income/spending analytics.
  final bool internal;
}

@immutable
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.target,
    required this.saved,
    required this.targetDate,
    this.autoMonthly,
  });
  final String id, name;
  final double target, saved;
  final DateTime targetDate;

  /// Standing instruction shown to the user. The prototype doesn't execute it.
  final double? autoMonthly;

  double get progress => target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0);

  SavingsGoal copyWith({double? saved}) =>
      SavingsGoal(id: id, name: name, target: target, saved: saved ?? this.saved, targetDate: targetDate, autoMonthly: autoMonthly);
}

enum LoanType { personal, vehicle, home, education }

@immutable
class Loan {
  const Loan({
    required this.id,
    required this.type,
    required this.principal,
    required this.outstanding,
    required this.annualRate,
    required this.monthlyPayment,
    required this.nextPaymentDate,
    required this.remainingMonths,
    required this.totalMonths,
    this.history = const [],
  });
  final String id;
  final LoanType type;
  final double principal, outstanding, annualRate, monthlyPayment;
  final DateTime nextPaymentDate;
  final int remainingMonths, totalMonths;

  /// Past instalments, newest first.
  final List<({DateTime date, double amount})> history;

  double get repaidFraction => principal <= 0 ? 0 : ((principal - outstanding) / principal).clamp(0.0, 1.0);

  /// Interest that has built up for the current month on what is still owed.
  double get monthlyInterest => outstanding * annualRate / 1200;

  /// What it takes to close the loan today: the balance plus this month's interest.
  double get payoffAmount => outstanding + monthlyInterest;

  bool get closed => outstanding <= 0.005;

  Loan copyWith({double? outstanding, int? remainingMonths, DateTime? nextPaymentDate, List<({DateTime date, double amount})>? history}) => Loan(
    id: id,
    type: type,
    principal: principal,
    outstanding: outstanding ?? this.outstanding,
    annualRate: annualRate,
    monthlyPayment: monthlyPayment,
    nextPaymentDate: nextPaymentDate ?? this.nextPaymentDate,
    remainingMonths: remainingMonths ?? this.remainingMonths,
    totalMonths: totalMonths,
    history: history ?? this.history,
  );
}
