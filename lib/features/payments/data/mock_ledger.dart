import 'dart:math';
import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';
import '../../../shared/models/service_models.dart';
import '../../fixed_deposits/domain/fixed_deposit.dart';
import '../../loans/domain/loan_math.dart';
import '../domain/recurrence.dart';
import '../domain/payment_repositories.dart';

/// In-memory stand-in for the bank's core system. It owns balances and enforces the
/// rules (funds, limits, recipient validity) so the UI never has to be trusted.
class MockLedger {
  MockLedger({DateTime? now}) : _now = now ?? DateTime.now() {
    accounts = [
      const BankAccount(id: 'a-sav', type: AccountType.savings, name: 'Savings Account', maskedNumber: '•••• 3021', balance: 428750),
      const BankAccount(id: 'a-cur', type: AccountType.current, name: 'Current Account', maskedNumber: '•••• 7745', balance: 85200),
      const BankAccount(id: 'a-fd', type: AccountType.fixedDeposit, name: 'Fixed Deposit', maskedNumber: '•••• 9902', balance: 1250000),
    ];
    transactions = _seed();
    loans = _seedLoans();
    fixedDeposits = [
      FixedDeposit(
        id: 'a-fd',
        name: 'Fixed Deposit',
        maskedNumber: '•••• 9902',
        principal: 1250000,
        rate: 9.5,
        termMonths: 12,
        startDate: addMonths(_now, -4),
        maturityDate: addMonths(_now, 8),
        renewal: FdRenewal.renewWithInterest,
        fundingAccountId: 'a-sav',
      ),
    ];
    goals = [
      SavingsGoal(id: 'g-car', name: 'New Car', target: 2500000, saved: 850000, targetDate: DateTime(_now.year + 2, _now.month, 1), autoMonthly: 25000),
      SavingsGoal(id: 'g-trip', name: 'Holiday', target: 300000, saved: 120000, targetDate: DateTime(_now.year, _now.month + 8, 1)),
    ];
  }

  /// A brand-new customer's books: one account holding the opening deposit, and no history, goals or loans.
  MockLedger.fresh({required double openingDeposit, required String accountLast4, AccountType accountType = AccountType.savings, DateTime? now})
    : _now = now ?? DateTime.now() {
    final current = accountType == AccountType.current;
    final id = current ? 'a-cur' : 'a-sav';
    accounts = [
      BankAccount(id: id, type: current ? AccountType.current : AccountType.savings, name: current ? 'Current Account' : 'Savings Account', maskedNumber: '•••• $accountLast4', balance: openingDeposit),
    ];
    transactions = [
      if (openingDeposit > 0)
        Transaction(
          id: 'OD${_now.millisecondsSinceEpoch % 100000000}',
          merchant: 'Opening deposit',
          category: TxCategory.income,
          amount: openingDeposit,
          date: _now,
          accountId: id,
          method: 'Account opening',
        ),
    ];
    goals = [];
    loans = [];
    fixedDeposits = [];
  }

  /// The bank's ceiling. [userDailyLimit] is what the customer chose, never above this.
  static const dailyTransferLimit = 500000.0;
  double userDailyLimit = dailyTransferLimit;

  final DateTime _now;
  late List<BankAccount> accounts;
  late List<Transaction> transactions;
  late List<SavingsGoal> goals;
  late List<Loan> loans;
  late List<FixedDeposit> fixedDeposits;
  final budgets = <TxCategory, double>{};
  final disputes = <Dispute>[];
  final loanApplications = <LoanApplication>[];
  final repeatDrafts = <String, PaymentDraft>{};

  /// Payments waiting for their date, and the instructions needed to run them.
  final scheduled = <ScheduledPayment>[];
  final _scheduledDrafts = <String, PaymentDraft>{};
  final _scheduledTxIds = <String, List<String>>{};
  final _anchorDays = <String, int>{};
  int _seq = 0;
  final _rng = Random();

  /// Only savings and current accounts can send money.
  bool canPayFrom(String id) {
    final type = accounts.where((a) => a.id == id).map((a) => a.type).firstOrNull;
    return type == AccountType.savings || type == AccountType.current;
  }

  BankAccount _account(String id) => accounts.firstWhere((a) => a.id == id);

  double _sentToday() {
    final today = DateTime(_now.year, _now.month, _now.day);
    return transactions
        .where((t) => t.category == TxCategory.transfer && t.amount < 0 && t.status == TxStatus.completed && !t.date.isBefore(today))
        .fold(0.0, (s, t) => s - t.amount);
  }

  /// [at] dates the transaction (used when a scheduled payment runs). [register] false is for the ledger's own
  /// bookkeeping: it must not create a second schedule entry for a payment that already has one.
  Receipt post(PaymentDraft d, {DateTime? at, bool register = true}) {
    final from = _account(d.fromAccountId);
    if (!canPayFrom(from.id)) {
      throw const PaymentException(PaymentFailure.unavailable, 'This account can’t be used for payments.');
    }
    if (d.amount <= 0) throw const PaymentException(PaymentFailure.unavailable, 'Enter an amount greater than zero.');
    if (d.kind == PaymentKind.transfer && d.toAccountId == null && RegExp(r'0{4}$').hasMatch(d.payeeDetail)) {
      throw const PaymentException(PaymentFailure.invalidRecipient, 'We couldn’t verify that account number. Check it and try again.');
    }
    // The next run of a repeating payment is queued before its day; funds are checked on the day, not now.
    if (!(d.isScheduled && !register) && d.total > from.balance) {
      throw const PaymentException(PaymentFailure.insufficientFunds, 'Your available balance is too low for this payment.');
    }
    final loan = d.kind == PaymentKind.loan ? _checkLoanPayment(d) : null;
    if (d.kind == PaymentKind.transfer && _sentToday() + d.amount > userDailyLimit) {
      throw PaymentException(PaymentFailure.limitExceeded, 'This would exceed your daily transfer limit of LKR ${userDailyLimit.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}.');
    }

    final id = 'ZB${_now.millisecondsSinceEpoch % 100000000}${(_seq++).toString().padLeft(2, '0')}${_rng.nextInt(90) + 10}';
    final doneAt = at ?? DateTime.now();
    if (!d.isScheduled) {
      _setBalance(from.id, from.balance - d.total);
      if (d.toAccountId != null) _setBalance(d.toAccountId!, _account(d.toAccountId!).balance + d.amount);
    }

    final own = d.toAccountId != null;
    final when = d.isScheduled ? d.scheduledFor! : doneAt;
    final status = d.isScheduled ? TxStatus.pending : TxStatus.completed;
    if (own) {
      transactions.insert(
        0,
        Transaction(
          id: '$id-in',
          merchant: 'Transfer from ${from.name}',
          category: TxCategory.transfer,
          amount: d.amount,
          date: when,
          status: status,
          accountId: d.toAccountId!,
          reference: d.reference,
          method: 'Own-account transfer',
          internal: true,
        ),
      );
    }
    transactions.insert(
      0,
      Transaction(
        id: id,
        merchant: d.isScheduled ? '${d.payee} (scheduled)' : d.payee,
        category: d.category,
        amount: -d.total,
        date: when,
        status: status,
        accountId: from.id,
        reference: d.reference,
        method: switch (d.kind) {
          PaymentKind.transfer => own ? 'Own-account transfer' : 'Bank transfer',
          PaymentKind.bill => 'Bill payment',
          PaymentKind.qr => 'QR payment',
          PaymentKind.loan => 'Loan instalment',
        },
        internal: own,
      ),
    );
    repeatDrafts[id] = d;
    if (d.isScheduled && register) {
      scheduled.add(
        ScheduledPayment(
          id: id,
          kind: d.kind,
          fromAccountId: from.id,
          payee: d.payee,
          payeeDetail: d.payeeDetail,
          amount: d.amount,
          fee: d.fee,
          reference: d.reference,
          nextRun: d.scheduledFor!,
          recurrence: d.recurrence,
        ),
      );
      _scheduledDrafts[id] = d;
      _scheduledTxIds[id] = [id, if (own) '$id-in'];
      _anchorDays[id] = d.scheduledFor!.day;
    }
    if (loan != null && !d.isScheduled) _applyLoanPayment(loan, d.amount, doneAt);

    return Receipt(
      id: id,
      kind: d.kind,
      status: status,
      payee: d.payee,
      amount: d.amount,
      fee: d.fee,
      fromName: from.name,
      fromMasked: from.maskedNumber,
      reference: d.reference,
      date: doneAt,
      details: [('To', d.payeeDetail), ...d.details],
      scheduled: d.isScheduled,
    );
  }


  // ---- scheduled payments --------------------------------------------------------------------------------------

  void _removeTransactions(Iterable<String> ids) {
    final gone = ids.toSet();
    transactions.removeWhere((t) => gone.contains(t.id));
  }

  /// Runs every scheduled payment whose day has come, as the bank's batch job would overnight.
  /// A repeating payment that missed several days catches up one run at a time.
  void runDue([DateTime? now]) {
    final clock = now ?? DateTime.now();
    for (var guard = 0; guard < 60; guard++) {
      final i = scheduled.indexWhere((s) => s.active && !s.nextRun.isAfter(clock));
      if (i < 0) break;
      _runOnce(i, clock);
    }
    _matureDeposits(clock);
  }

  void _runOnce(int i, DateTime clock) {
    final sp = scheduled[i];
    final draft = _scheduledDrafts[sp.id]!;
    _removeTransactions(_scheduledTxIds[sp.id] ?? const []);
    var next = sp;
    try {
      post(draft.asImmediate(), at: sp.nextRun, register: false);
      next = next.copyWith(runCount: sp.runCount + 1, clearMessage: true);
    } on PaymentException catch (e) {
      transactions.insert(
        0,
        Transaction(
          id: 'SF${sp.id}-${sp.runCount}-${_seq++}',
          merchant: '${draft.payee} (scheduled) – not paid',
          category: draft.category,
          amount: -draft.total,
          date: sp.nextRun,
          status: TxStatus.failed,
          accountId: draft.fromAccountId,
          reference: e.message,
          method: 'Scheduled payment',
        ),
      );
      next = next.copyWith(lastMessage: e.message);
    }
    if (sp.recurrence == Recurrence.once) {
      _scheduledTxIds[sp.id] = const [];
      scheduled[i] = next.copyWith(status: next.lastMessage == null ? ScheduleStatus.completed : ScheduleStatus.failed);
      return;
    }
    final upcoming = nextOccurrence(sp.nextRun, sp.recurrence, anchorDay: _anchorDays[sp.id]);
    scheduled[i] = next.copyWith(nextRun: upcoming);
    if (upcoming.isAfter(clock)) {
      // Queue the next run so it shows in history as pending, like the first one did.
      final r = post(draft.scheduledAt(upcoming), register: false);
      _scheduledTxIds[sp.id] = [r.id, if (draft.toAccountId != null) '${r.id}-in'];
    } else {
      _scheduledTxIds[sp.id] = const [];
    }
  }

  /// Stops a scheduled payment and clears its pending entry from history.
  void cancelScheduled(String id) {
    final i = scheduled.indexWhere((s) => s.id == id);
    if (i < 0) throw const PaymentException(PaymentFailure.unavailable, 'We couldn’t find that scheduled payment.');
    if (!scheduled[i].active) throw const PaymentException(PaymentFailure.unavailable, 'That payment has already finished.');
    _removeTransactions(_scheduledTxIds[id] ?? const []);
    _scheduledTxIds[id] = const [];
    scheduled[i] = scheduled[i].copyWith(status: ScheduleStatus.cancelled);
  }

  List<Loan> _seedLoans() {
    Loan build(String id, LoanType type, double principal, double outstanding, double rate, int total, int remaining) {
      final monthly = monthlyInstallment(principal, rate, total);
      return Loan(
        id: id,
        type: type,
        principal: principal,
        outstanding: outstanding,
        annualRate: rate,
        monthlyPayment: monthly,
        nextPaymentDate: DateTime(_now.year, _now.month + 1, 5),
        remainingMonths: remaining,
        totalMonths: total,
        history: [
          for (var i = 0; i < 6; i++) (date: DateTime(_now.year, _now.month - i, 5), amount: monthly),
        ],
      );
    }

    return [
      build('l-veh', LoanType.vehicle, 3500000, 2150000, 13.5, 60, 36),
      build('l-per', LoanType.personal, 600000, 310000, 15, 24, 12),
    ];
  }

  /// Rules for paying a loan: it must exist and be open, and the money cannot exceed the payoff amount.
  Loan _checkLoanPayment(PaymentDraft d) {
    final loan = loans.where((l) => l.id == d.loanId).firstOrNull;
    if (loan == null) throw const PaymentException(PaymentFailure.invalidRecipient, 'We couldn’t find that loan.');
    if (loan.closed) throw const PaymentException(PaymentFailure.unavailable, 'This loan is already fully repaid.');
    if (d.amount > loan.payoffAmount + 0.01) {
      throw PaymentException(PaymentFailure.unavailable, 'That is more than is needed to settle this loan (LKR ${loan.payoffAmount.toStringAsFixed(2)}).');
    }
    if (d.isScheduled) throw const PaymentException(PaymentFailure.unavailable, 'Loan payments can’t be scheduled yet. Pay now instead.');
    return loan;
  }

  /// Interest for the month is paid first; what is left reduces the balance. Paying at least the
  /// instalment (or settling in full) counts as that month's instalment; smaller or extra amounts only change the balance.
  void _applyLoanPayment(Loan loan, double amount, DateTime at) {
    final principalPaid = (amount - loan.monthlyInterest).clamp(0.0, loan.outstanding);
    final outstanding = loan.outstanding - principalPaid;
    final settled = outstanding <= 0.005;
    final instalmentMet = settled || amount >= loan.monthlyPayment - 0.005;
    final updated = loan.copyWith(
      outstanding: settled ? 0 : outstanding,
      remainingMonths: settled ? 0 : (instalmentMet ? loan.remainingMonths - 1 : loan.remainingMonths),
      nextPaymentDate: instalmentMet ? DateTime(loan.nextPaymentDate.year, loan.nextPaymentDate.month + 1, loan.nextPaymentDate.day) : null,
      history: [(date: at, amount: amount), ...loan.history],
    );
    loans = [for (final l in loans) l.id == loan.id ? updated : l];
  }

  /// Moves money into a savings goal (positive [amount]) or back out (negative).
  void moveGoal(String goalId, String accountId, double amount) {
    final goal = goals.firstWhere((g) => g.id == goalId);
    final account = _account(accountId);
    if (!canPayFrom(accountId)) {
      throw const PaymentException(PaymentFailure.unavailable, 'This account can’t be used for savings goals.');
    }
    if (amount == 0) throw const PaymentException(PaymentFailure.unavailable, 'Enter an amount greater than zero.');
    if (amount > 0 && amount > account.balance) {
      throw const PaymentException(PaymentFailure.insufficientFunds, 'Your available balance is too low for this deposit.');
    }
    if (amount < 0 && -amount > goal.saved) {
      throw const PaymentException(PaymentFailure.unavailable, 'You can’t withdraw more than you’ve saved in this goal.');
    }
    _setBalance(accountId, account.balance - amount);
    goals = [for (final g in goals) g.id == goalId ? g.copyWith(saved: g.saved + amount) : g];
    transactions.insert(
      0,
      Transaction(
        id: 'SG${_now.millisecondsSinceEpoch % 100000000}${_seq++}',
        merchant: amount > 0 ? 'Saved to ${goal.name}' : 'Withdrawn from ${goal.name}',
        category: TxCategory.transfer,
        amount: -amount,
        date: DateTime.now(),
        accountId: accountId,
        method: 'Savings goal',
        internal: true,
      ),
    );
  }

  void addGoal(SavingsGoal goal) => goals = [...goals, goal];

  void _setBalance(String id, double balance) {
    accounts = [for (final a in accounts) a.id == id ? a.copyWith(balance: balance) : a];
  }

  // ---- opening accounts ----------------------------------------------------------------------------------------

  BankAccount openAccount({required AccountType type, required String name, required String fromAccountId, required double amount}) {
    if (type == AccountType.fixedDeposit) {
      throw const PaymentException(PaymentFailure.unavailable, 'Open fixed deposits from the Fixed deposits section.');
    }
    if (type == AccountType.foreignCurrency) {
      throw const PaymentException(PaymentFailure.unavailable, 'Foreign currency accounts are opened at a branch.');
    }
    final from = _fundingAccount(fromAccountId, 'Choose a savings or current account to fund the new account from.');
    _checkRoomForAnotherAccount();
    if (amount < minNewAccountDeposit) {
      throw PaymentException(PaymentFailure.unavailable, 'The minimum to open this account is ${_lkr(minNewAccountDeposit)}.');
    }
    if (amount > from.balance) {
      throw const PaymentException(PaymentFailure.insufficientFunds, 'Your available balance is too low for that deposit.');
    }
    final seq = _seq++;
    final id = 'a-${type == AccountType.current ? 'cur' : 'sav'}-${seq + 1}';
    final cleanName = name.trim().isEmpty ? (type == AccountType.current ? 'Current Account' : 'Savings Account') : name.trim();
    final account = BankAccount(id: id, type: type, name: cleanName, maskedNumber: '•••• ${_newLast4(seq)}', balance: amount);
    _moveIntoNewAccount(from, account, amount, 'Transfer to $cleanName', 'Opening deposit');
    return account;
  }

  // ---- fixed deposits ------------------------------------------------------------------------------------------

  FixedDeposit openFixedDeposit({required String fromAccountId, required double amount, required int termMonths, required FdRenewal renewal}) {
    final from = _fundingAccount(fromAccountId, 'Choose a savings or current account to fund the deposit from.');
    _checkRoomForAnotherAccount();
    if (!isValidFdTerm(termMonths)) {
      throw const PaymentException(PaymentFailure.unavailable, 'Choose 3, 6 or 12 months, or a whole number of years from 24 to 120 months.');
    }
    if (amount < minFixedDeposit) {
      throw PaymentException(PaymentFailure.unavailable, 'The minimum fixed deposit is ${_lkr(minFixedDeposit)}.');
    }
    if (amount > from.balance) {
      throw const PaymentException(PaymentFailure.insufficientFunds, 'Your available balance is too low for that deposit.');
    }
    final seq = _seq++;
    final now = DateTime.now();
    final account = BankAccount(id: 'a-fd-${seq + 1}', type: AccountType.fixedDeposit, name: 'Fixed Deposit', maskedNumber: '•••• ${_newLast4(seq)}', balance: amount);
    _moveIntoNewAccount(from, account, amount, 'Transfer to Fixed Deposit', 'Fixed deposit opened');
    final fd = FixedDeposit(
      id: account.id,
      name: account.name,
      maskedNumber: account.maskedNumber,
      principal: amount,
      rate: fixedDepositRateFor(termMonths),
      termMonths: termMonths,
      startDate: now,
      maturityDate: addMonths(now, termMonths),
      renewal: renewal,
      fundingAccountId: from.id,
    );
    fixedDeposits = [...fixedDeposits, fd];
    return fd;
  }

  /// Pays or rolls over every deposit whose term has ended, as the bank's overnight run would.
  void _matureDeposits(DateTime clock) {
    for (var guard = 0; guard < 40; guard++) {
      final i = fixedDeposits.indexWhere((d) => d.active && !d.maturityDate.isAfter(clock));
      if (i < 0) return;
      _matureOnce(i);
    }
  }

  void _matureOnce(int i) {
    final d = fixedDeposits[i];
    final interest = d.interestAtMaturity;
    final when = d.maturityDate;
    final fund = accounts.where((a) => a.id == d.fundingAccountId && canPayFrom(a.id)).firstOrNull ?? accounts.where((a) => canPayFrom(a.id)).firstOrNull;
    var mode = d.renewal;
    // With nowhere to pay it, the interest stays in the deposit rather than going missing.
    if (fund == null && mode != FdRenewal.renewWithInterest) mode = FdRenewal.renewWithInterest;
    var n = 0;
    Transaction tx(String accountId, String merchant, double amount, {required bool internal, TxCategory category = TxCategory.income}) =>
        Transaction(id: 'FD${d.id}-${when.millisecondsSinceEpoch}-${n++}', merchant: merchant, category: category, amount: amount, date: when, accountId: accountId, method: 'Fixed deposit', internal: internal);

    FixedDeposit next;
    switch (mode) {
      case FdRenewal.renewWithInterest:
        _setBalance(d.id, _account(d.id).balance + interest);
        transactions.insert(0, tx(d.id, 'Fixed deposit interest', interest, internal: false));
        next = _renewed(d, d.principal + interest, when);
      case FdRenewal.renewPrincipalOnly:
        _setBalance(fund!.id, _account(fund.id).balance + interest);
        transactions.insert(0, tx(fund.id, 'Fixed deposit interest', interest, internal: false));
        next = _renewed(d, d.principal, when);
      case FdRenewal.payOut:
        _setBalance(fund!.id, _account(fund.id).balance + d.principal + interest);
        _setBalance(d.id, 0);
        transactions.insertAll(0, [
          tx(d.id, 'Fixed deposit matured', -d.principal, internal: true, category: TxCategory.transfer),
          tx(fund.id, 'From fixed deposit', d.principal, internal: true, category: TxCategory.transfer),
          tx(fund.id, 'Fixed deposit interest', interest, internal: false),
        ]);
        next = d.copyWith(status: FdStatus.matured, paidOut: d.principal + interest);
    }
    fixedDeposits = [for (var k = 0; k < fixedDeposits.length; k++) k == i ? next : fixedDeposits[k]];
  }

  FixedDeposit _renewed(FixedDeposit d, double principal, DateTime from) =>
      d.copyWith(principal: principal, rate: fixedDepositRateFor(d.termMonths), startDate: from, maturityDate: addMonths(from, d.termMonths), renewals: d.renewals + 1);

  // ---- shared by account and deposit opening ---------------------------------------------------------------------

  BankAccount _fundingAccount(String id, String message) {
    final a = accounts.where((x) => x.id == id).firstOrNull;
    if (a == null || !canPayFrom(a.id)) throw PaymentException(PaymentFailure.unavailable, message);
    return a;
  }

  void _checkRoomForAnotherAccount() {
    if (accounts.length >= maxAccountsPerCustomer) {
      throw const PaymentException(PaymentFailure.unavailable, 'You can have up to $maxAccountsPerCustomer accounts. Close one at a branch to open another.');
    }
  }

  String _newLast4(int seq) => (1000 + (DateTime.now().millisecondsSinceEpoch + seq * 7919) % 8999).toString();

  String _lkr(double v) => 'LKR ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

  /// Moves [amount] out of [from] into the brand-new [account], and records both sides as an own-account move.
  void _moveIntoNewAccount(BankAccount from, BankAccount account, double amount, String outLabel, String inLabel) {
    final now = DateTime.now();
    accounts = [for (final a in accounts) a.id == from.id ? a.copyWith(balance: a.balance - amount) : a, account];
    transactions.insertAll(0, [
      Transaction(id: 'AO${account.id}-out', merchant: outLabel, category: TxCategory.transfer, amount: -amount, date: now, accountId: from.id, method: 'Account opening', internal: true),
      Transaction(id: 'AO${account.id}-in', merchant: inLabel, category: TxCategory.transfer, amount: amount, date: now, accountId: account.id, method: 'Account opening', internal: true),
    ]);
  }

  // ---- loan applications ---------------------------------------------------------------------------------------

  LoanApplication applyForLoan(LoanApplicationRequest r) {
    final lim = loanLimits(r.type);
    if (r.amount < lim.min || r.amount > lim.max) {
      throw const LoanApplicationException('That amount is outside what this loan type allows. Adjust the amount and try again.');
    }
    if (r.termMonths < lim.minMonths || r.termMonths > lim.maxMonths) {
      throw const LoanApplicationException('That term is outside what this loan type allows.');
    }
    if (r.monthlyIncome <= 0) throw const LoanApplicationException('Enter your monthly income.');
    if (loanApplications.where((a) => a.type == r.type).length >= 2) {
      throw const LoanApplicationException('You already have two applications for this loan type under review. Wait for a decision before applying again.');
    }
    final now = DateTime.now();
    final app = LoanApplication(
      id: 'LA${now.millisecondsSinceEpoch % 100000000}${_seq++}',
      type: r.type,
      amount: r.amount,
      termMonths: r.termMonths,
      monthlyIncome: r.monthlyIncome,
      employment: r.employment,
      purpose: r.purpose.trim(),
      createdAt: now,
      indicativeMonthly: monthlyInstallment(r.amount, _indicativeRate(r.type), r.termMonths),
    );
    loanApplications.insert(0, app);
    return app;
  }

  static double _indicativeRate(LoanType t) => switch (t) {
    LoanType.personal => 15,
    LoanType.vehicle => 13.5,
    LoanType.home => 11,
    LoanType.education => 9,
  };

  // ---- disputes ------------------------------------------------------------------------------------------------

  Dispute raiseDispute(Transaction t, DisputeReason reason, String details) {
    final known = transactions.where((x) => x.id == t.id).firstOrNull;
    if (known == null) throw const DisputeException('We couldn’t find that transaction.');
    final blocked = disputeBlockReason(known);
    if (blocked != null) throw DisputeException(blocked);
    if (disputes.any((d) => d.transactionId == known.id)) {
      throw const DisputeException('You’ve already raised a dispute about this payment. You can follow it under My disputes.');
    }
    final now = DateTime.now();
    final d = Dispute(
      id: 'DSP${now.millisecondsSinceEpoch % 10000000}${_seq++}',
      transactionId: known.id,
      merchant: known.merchant,
      amount: known.amount.abs(),
      reason: reason,
      details: details.trim(),
      createdAt: now,
    );
    disputes.insert(0, d);
    return d;
  }

  Transaction _tx(String id, String merchant, TxCategory c, double amount, DateTime date, {TxStatus status = TxStatus.completed}) {
    final (account, method) = switch (c) {
      TxCategory.bills || TxCategory.entertainment => ('a-cur', 'Online payment'),
      TxCategory.income => ('a-sav', 'Bank credit'),
      TxCategory.transfer => ('a-sav', 'Bank transfer'),
      _ => ('a-sav', 'Debit card •••• 4821'),
    };
    return Transaction(id: id, merchant: merchant, category: c, amount: amount, date: date, status: status, accountId: account, method: method);
  }

  List<Transaction> _seed() {
    // Recent activity: (merchant, category, amount, days ago, hour).
    const recent = <(String, TxCategory, double, int, int)>[
      ('Dialog Axiata', TxCategory.bills, -1500, 0, 9),
      ('Starbucks', TxCategory.food, -1450, 0, 0),
      ('Dividend credit', TxCategory.income, 6200, 0, 0),
      ('Salary — NovaCore Techs', TxCategory.income, 185000, 1, 8),
      ('Uber', TxCategory.transport, -2450, 1, 19),
      ('Keells Supermarket', TxCategory.food, -8450, 2, 17),
      ('Netflix', TxCategory.entertainment, -2490, 3, 6),
      ('Ceylon Electricity Board', TxCategory.bills, -6840, 4, 11),
      ('Cargills Food City', TxCategory.food, -4120, 5, 18),
      ('Transfer from Nimal', TxCategory.transfer, 15000, 6, 13),
      ('PickMe', TxCategory.transport, -1380, 6, 21),
      ('Odel', TxCategory.shopping, -12900, 8, 15),
      ('Healthguard Pharmacy', TxCategory.health, -3260, 9, 12),
      ('Spotify', TxCategory.entertainment, -990, 10, 7),
      ('Udemy', TxCategory.education, -4500, 11, 20),
      ('Burger King', TxCategory.food, -3150, 12, 13),
      ('SLT Fibre', TxCategory.bills, -5990, 13, 10),
      ('Interest credit', TxCategory.income, 2840, 14, 0),
      ('Uber', TxCategory.transport, -1920, 15, 8),
      ('Arpico', TxCategory.shopping, -9720, 16, 16),
      ('Nawaloka Hospital', TxCategory.health, -7400, 18, 11),
      ('Transfer to Kamala', TxCategory.transfer, -20000, 19, 14),
      ('Water Board', TxCategory.bills, -1780, 21, 9),
      ('Cinnamon Grand Café', TxCategory.food, -6250, 22, 20),
      ('Freelance payment', TxCategory.income, 42000, 24, 12),
      ('Amazon', TxCategory.shopping, -15600, 26, 22),
      ('Lanka Hospitals', TxCategory.health, -5200, 28, 10),
    ];
    final out = <Transaction>[
      for (var i = 0; i < recent.length; i++)
        _tx(
          'TX${482100 + i * 37}',
          recent[i].$1,
          recent[i].$2,
          recent[i].$3,
          DateTime(_now.year, _now.month, _now.day, recent[i].$5).subtract(Duration(days: recent[i].$4)),
          status: i == 0 ? TxStatus.pending : TxStatus.completed,
        ),
    ];
    // Older months are generated on the calendar so the monthly charts have shape.
    var n = 0;
    for (var m = 2; m <= 5; m++) {
      final rows = <(int, String, TxCategory, double)>[
        (1, 'Salary — NovaCore Techs', TxCategory.income, 185000),
        (3, 'Keells Supermarket', TxCategory.food, -(7000.0 + m * 350)),
        (5, 'Ceylon Electricity Board', TxCategory.bills, -(6200.0 + m * 210)),
        (8, 'Uber', TxCategory.transport, -(2000.0 + (m % 3) * 400)),
        (12, 'Netflix', TxCategory.entertainment, -2490),
        (15, 'Odel', TxCategory.shopping, -(8000.0 + m * 1700)),
        (18, 'Cargills Food City', TxCategory.food, -(4200.0 + m * 150)),
        (21, 'Healthguard Pharmacy', TxCategory.health, -(2500.0 + m * 300)),
        (24, 'SLT Fibre', TxCategory.bills, -5990),
        (26, 'Cinnamon Grand Café', TxCategory.food, -(4800.0 + (m % 2) * 1500)),
        if (m == 3) (10, 'Udemy', TxCategory.education, -4500),
      ];
      for (final (day, merchant, cat, amount) in rows) {
        out.add(_tx('TX${470000 + n++ * 11}', merchant, cat, amount, DateTime(_now.year, _now.month - m, day, 12)));
      }
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }
}

class MockScheduledPaymentRepository implements ScheduledPaymentRepository {
  MockScheduledPaymentRepository(this._ledger);
  final MockLedger _ledger;

  @override
  Future<List<ScheduledPayment>> scheduled() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _ledger.runDue();
    final list = [..._ledger.scheduled]..sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.nextRun.compareTo(b.nextRun);
    });
    return List.unmodifiable(list);
  }

  @override
  Future<void> cancel(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _ledger.cancelScheduled(id);
  }
}

class MockPaymentRepository implements PaymentRepository {
  MockPaymentRepository(this._ledger, {this.latency = const Duration(milliseconds: 1600)});
  final MockLedger _ledger;
  final Duration latency;

  @override
  Future<Receipt> pay(PaymentDraft draft) async {
    await Future<void>.delayed(latency);
    return _ledger.post(draft);
  }
}

class MockBeneficiaryRepository implements BeneficiaryRepository {
  MockBeneficiaryRepository({List<Beneficiary>? seed}) : _items = [...(seed ?? _demoBeneficiaries)];

  static const _demoBeneficiaries = <Beneficiary>[
    Beneficiary(id: 'b-1', bank: 'Commercial Bank', accountNumber: '8001234567', name: 'Nimal Perera', nickname: 'Nimal', favorite: true),
    Beneficiary(id: 'b-2', bank: 'Bank of Ceylon', accountNumber: '7712340988', name: 'Kamala Silva'),
    Beneficiary(id: 'b-3', bank: 'Zentrix Bank', accountNumber: '1000200030', name: 'Sunil Fernando', nickname: 'Landlord'),
  ];

  final List<Beneficiary> _items;


  @override
  Future<List<Beneficiary>> beneficiaries() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_items);
  }

  @override
  Future<void> add(Beneficiary b) async {
    if (_items.any((x) => x.accountNumber == b.accountNumber && x.bank == b.bank)) {
      throw const PaymentException(PaymentFailure.invalidRecipient, 'That beneficiary is already saved.');
    }
    _items.add(b);
  }

  @override
  Future<void> update(Beneficiary b) async {
    final i = _items.indexWhere((x) => x.id == b.id);
    if (i >= 0) _items[i] = b;
  }

  @override
  Future<void> remove(String id) async => _items.removeWhere((x) => x.id == id);
}
