import 'package:flutter/foundation.dart';
import 'models.dart';

// ---- Disputes -------------------------------------------------------------------------------------------------

enum DisputeReason { notMine, wrongAmount, duplicate, notReceived, other }

enum DisputeStatus { received, inReview }

String disputeReasonLabel(DisputeReason r) => switch (r) {
  DisputeReason.notMine => 'I don’t recognise this transaction',
  DisputeReason.wrongAmount => 'I was charged the wrong amount',
  DisputeReason.duplicate => 'I was charged twice',
  DisputeReason.notReceived => 'I didn’t get what I paid for',
  DisputeReason.other => 'Something else',
};

/// A customer's challenge to a payment on their account. This records and tracks the request;
/// the bank decides the outcome, and no money moves because of it here.
@immutable
class Dispute {
  const Dispute({
    required this.id,
    required this.transactionId,
    required this.merchant,
    required this.amount,
    required this.reason,
    required this.createdAt,
    this.details = '',
  });

  /// The reference the customer quotes when they call.
  final String id, transactionId, merchant, details;
  final double amount;
  final DisputeReason reason;
  final DateTime createdAt;

  /// Received for the first day, then in review. (A real bank reports its own status; this is the prototype's clock.)
  DisputeStatus statusAt(DateTime now) => now.difference(createdAt) >= const Duration(days: 1) ? DisputeStatus.inReview : DisputeStatus.received;
}

class DisputeException implements Exception {
  const DisputeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Why a transaction can't be disputed, or null when it can. Only settled payments out of the account qualify.
String? disputeBlockReason(Transaction t) {
  if (t.amount >= 0) return 'Only payments you made can be disputed. For a deposit you don’t recognise, contact the bank.';
  if (t.status == TxStatus.pending) return 'This payment is still pending. If it’s wrong, wait until it settles, or cancel it from Scheduled payments.';
  if (t.status == TxStatus.failed) return 'This payment didn’t go through, so no money was taken.';
  if (t.internal) return 'This is a move between your own accounts, so there’s nothing to dispute.';
  return null;
}

// ---- Extra accounts -------------------------------------------------------------------------------------------

const minNewAccountDeposit = 1000.0;
const maxAccountsPerCustomer = 6;

// ---- Loan applications ----------------------------------------------------------------------------------------

enum LoanApplicationStatus { received, underReview }

@immutable
class LoanApplication {
  const LoanApplication({
    required this.id,
    required this.type,
    required this.amount,
    required this.termMonths,
    required this.monthlyIncome,
    required this.employment,
    required this.createdAt,
    this.purpose = '',
    this.indicativeMonthly = 0,
  });
  final String id, employment, purpose;
  final LoanType type;
  final double amount, monthlyIncome, indicativeMonthly;
  final int termMonths;
  final DateTime createdAt;

  /// Always "received" or "under review": only the bank can approve a loan, and this app never pretends otherwise.
  LoanApplicationStatus statusAt(DateTime now) =>
      now.difference(createdAt) >= const Duration(days: 1) ? LoanApplicationStatus.underReview : LoanApplicationStatus.received;
}

/// What the customer fills in; the bank turns it into a [LoanApplication].
@immutable
class LoanApplicationRequest {
  const LoanApplicationRequest({
    required this.type,
    required this.amount,
    required this.termMonths,
    required this.monthlyIncome,
    required this.employment,
    this.purpose = '',
  });
  final LoanType type;
  final double amount, monthlyIncome;
  final int termMonths;
  final String employment, purpose;
}

class LoanApplicationException implements Exception {
  const LoanApplicationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Loan sizes the app will accept an application for, per type. The bank's own policy is applied on review.
({double min, double max, int minMonths, int maxMonths}) loanLimits(LoanType t) => switch (t) {
  LoanType.personal => (min: 50000, max: 3000000, minMonths: 6, maxMonths: 60),
  LoanType.vehicle => (min: 500000, max: 15000000, minMonths: 12, maxMonths: 84),
  LoanType.home => (min: 1000000, max: 50000000, minMonths: 60, maxMonths: 300),
  LoanType.education => (min: 100000, max: 5000000, minMonths: 12, maxMonths: 120),
};

/// A plain affordability hint: the instalment as a share of monthly income. It is not a credit decision.
enum Affordability { comfortable, stretched, unlikely }

Affordability affordabilityOf(double monthlyInstalment, double monthlyIncome) {
  if (monthlyIncome <= 0) return Affordability.unlikely;
  final share = monthlyInstalment / monthlyIncome;
  if (share <= 0.35) return Affordability.comfortable;
  if (share <= 0.5) return Affordability.stretched;
  return Affordability.unlikely;
}
