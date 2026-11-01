import 'dart:math';

/// Standard reducing-balance instalment: P·r·(1+r)^n / ((1+r)^n − 1), r = annual % / 12.
double monthlyInstallment(double principal, double annualRatePercent, int months) {
  if (principal <= 0 || months <= 0) return 0;
  final r = annualRatePercent / 1200;
  if (r == 0) return principal / months;
  final growth = pow(1 + r, months).toDouble();
  return principal * r * growth / (growth - 1);
}

class LoanEstimate {
  const LoanEstimate({required this.monthly, required this.totalPayable, required this.totalInterest});
  final double monthly, totalPayable, totalInterest;
}

LoanEstimate estimateLoan(double principal, double annualRatePercent, int months) {
  final monthly = monthlyInstallment(principal, annualRatePercent, months);
  final total = monthly * months;
  return LoanEstimate(monthly: monthly, totalPayable: total, totalInterest: max(0, total - principal));
}
