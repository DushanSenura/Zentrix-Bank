import 'package:flutter/foundation.dart';

// ---- Terms and rates ------------------------------------------------------------------------------------------

/// The quick choices. Anything longer is entered as a number of months, in whole years: 24, 36, 48 …
const fdQuickTerms = [3, 6, 12];
const fdMinLongTerm = 24;
const fdMaxTerm = 120;
const minFixedDeposit = 10000.0;

/// Whether [months] can be opened: 3, 6 or 12, or a whole number of years from 2 up to 10.
bool isValidFdTerm(int months) => fdQuickTerms.contains(months) || (months >= fdMinLongTerm && months <= fdMaxTerm && months % 12 == 0);

/// Why a typed-in number of months can't be used, or null when it can. For the "more than 12 months" box.
String? validateLongFdMonths(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 'Enter the number of months.';
  final n = int.tryParse(text);
  if (n == null) return 'Use whole numbers only, like 24, 36 or 48.';
  if (n <= 12) return 'For 12 months or fewer, pick one of the choices above.';
  if (n % 12 != 0) return 'Use whole years in months: 24, 36, 48 …';
  if (n > fdMaxTerm) return 'The longest term is $fdMaxTerm months (10 years).';
  return null;
}

/// Indicative annual rate for a term, as a percentage. **Sample values for the prototype, not a real rate card:**
/// the bank confirms the actual rate when it opens the deposit.
double fixedDepositRateFor(int months) {
  if (months <= 3) return 7.5;
  if (months <= 6) return 8.5;
  if (months <= 12) return 9.5;
  if (months <= 24) return 10.0;
  if (months <= 36) return 10.25;
  if (months <= 48) return 10.5;
  if (months <= 60) return 10.75;
  return 11.0;
}

String fdTermLabel(int months) {
  if (months < 24 || months % 12 != 0) return '$months months';
  return '$months months (${months ~/ 12} years)';
}

/// [months] later than [from], keeping the day of the month where it exists and otherwise using the last day
/// (31 Jan + 1 month = 28 Feb, not 3 Mar).
DateTime addMonths(DateTime from, int months) {
  final total = from.month - 1 + months;
  final year = from.year + (total / 12).floor(); // floor, not truncate, so stepping back across a year works
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, from.day > lastDay ? lastDay : from.day, from.hour, from.minute);
}

/// Simple interest for the whole term: principal × rate × years, rounded to the cent.
double fixedDepositInterest(double principal, double annualRatePercent, int months) =>
    (principal * annualRatePercent / 100 * months / 12 * 100).round() / 100;

// ---- The deposit ----------------------------------------------------------------------------------------------

/// What happens when the term ends.
///
/// The app offers two choices, [renewWithInterest] and [renewPrincipalOnly] (shown as "Renew without interest").
/// [payOut] can't be chosen here, but a deposit arranged some other way (for example at a branch) can carry it, so it is
/// still understood and shown correctly.
enum FdRenewal { renewWithInterest, renewPrincipalOnly, payOut }

/// The options a customer can pick from, in the order they're shown.
const fdRenewalChoices = [FdRenewal.renewWithInterest, FdRenewal.renewPrincipalOnly];

String fdRenewalLabel(FdRenewal r) => switch (r) {
  FdRenewal.renewWithInterest => 'Renew with interest',
  FdRenewal.renewPrincipalOnly => 'Renew without interest',
  FdRenewal.payOut => 'Paid out at maturity',
};

String fdRenewalHint(FdRenewal r) => switch (r) {
  FdRenewal.renewWithInterest => 'The deposit and its interest start a new term together, so your interest earns interest.',
  FdRenewal.renewPrincipalOnly => 'Only the original amount starts a new term. The interest is paid to your account.',
  FdRenewal.payOut => 'The deposit and its interest are paid to your account on the maturity date.',
};

enum FdStatus { active, matured }

@immutable
class FixedDeposit {
  const FixedDeposit({
    required this.id,
    required this.name,
    required this.maskedNumber,
    required this.principal,
    required this.rate,
    required this.termMonths,
    required this.startDate,
    required this.maturityDate,
    required this.renewal,
    required this.fundingAccountId,
    this.status = FdStatus.active,
    this.renewals = 0,
    this.paidOut = 0,
  });

  /// Also the id of the deposit's account, so it shows up with the rest of your accounts and in your balance.
  final String id, name, maskedNumber, fundingAccountId;
  final double principal, rate;
  final int termMonths;
  final DateTime startDate, maturityDate;
  final FdRenewal renewal;
  final FdStatus status;

  /// How many times it has rolled into a new term.
  final int renewals;

  /// For a matured deposit: what was paid to the account.
  final double paidOut;

  bool get active => status == FdStatus.active;
  double get interestAtMaturity => fixedDepositInterest(principal, rate, termMonths);
  double get valueAtMaturity => principal + interestAtMaturity;

  /// How far through the current term, 0…1.
  double progressAt(DateTime now) {
    final total = maturityDate.difference(startDate).inSeconds;
    if (total <= 0) return 1;
    return (now.difference(startDate).inSeconds / total).clamp(0.0, 1.0);
  }

  int daysLeftAt(DateTime now) {
    final d = DateTime(maturityDate.year, maturityDate.month, maturityDate.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    return d < 0 ? 0 : d;
  }

  FixedDeposit copyWith({
    double? principal,
    double? rate,
    DateTime? startDate,
    DateTime? maturityDate,
    FdRenewal? renewal,
    FdStatus? status,
    int? renewals,
    double? paidOut,
  }) => FixedDeposit(
    id: id,
    name: name,
    maskedNumber: maskedNumber,
    principal: principal ?? this.principal,
    rate: rate ?? this.rate,
    termMonths: termMonths,
    startDate: startDate ?? this.startDate,
    maturityDate: maturityDate ?? this.maturityDate,
    renewal: renewal ?? this.renewal,
    fundingAccountId: fundingAccountId,
    status: status ?? this.status,
    renewals: renewals ?? this.renewals,
    paidOut: paidOut ?? this.paidOut,
  );
}

/// A fixed deposit can't be changed after it is opened: term, rate and what happens at maturity are fixed on the day.
abstract interface class FixedDepositRepository {
  /// Active deposits first (soonest maturity first), then matured ones.
  Future<List<FixedDeposit>> deposits();

  /// Opens a deposit funded from [fromAccountId]. Throws `PaymentException` when the bank refuses.
  Future<FixedDeposit> open({required String fromAccountId, required double amount, required int termMonths, required FdRenewal renewal});
}
