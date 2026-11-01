import '../../shared/models/engagement_models.dart';
import '../../features/fixed_deposits/domain/fixed_deposit.dart';
import '../../shared/models/models.dart';
import '../../shared/models/service_models.dart';
import '../../shared/models/payment_models.dart';
import 'api_client.dart';
import 'api_exceptions.dart';

/// JSON ⇄ domain mapping for the REST contract in `docs/api_contract.md`.
/// Money travels as integer minor units (cents) so no float ever represents an amount on the wire;
/// the UI models still use `double`, converted only here.
///
/// A malformed payload becomes a [ServerException] rather than a crash.

/// Mobile top-up was removed from the app. A server that still reports it is read as an ordinary bill payment.
const _legacyKinds = {'top_up': PaymentKind.bill, 'topUp': PaymentKind.bill};

ServerException _bad(String what) => ServerException('The bank sent an unexpected response ($what).');

T _get<T>(Json j, String key) {
  final v = j[key];
  if (v is T) return v;
  throw _bad(key);
}

T? _opt<T>(Json j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is T) return v;
  throw _bad(key);
}

double fromMinor(int minor) => minor / 100;
int toMinor(double major) => (major * 100).round();

double _money(Json j, String key) => fromMinor(_get<num>(j, key).round());

E _enum<E extends Enum>(List<E> values, Json j, String key, {Map<String, E> aliases = const {}}) {
  final raw = _get<String>(j, key);
  final hit = aliases[raw] ?? values.where((v) => v.name == raw).firstOrNull;
  if (hit == null) throw _bad(key);
  return hit;
}

List<Json> items(Json response) {
  final list = _get<List<dynamic>>(response, 'items');
  return [
    for (final e in list)
      if (e is Json) e else throw _bad('items'),
  ];
}

DateTime _date(Json j, String key) => DateTime.tryParse(_get<String>(j, key)) ?? (throw _bad(key));

AppUser userFromJson(Json j) => AppUser(
  id: _get(j, 'id'),
  fullName: _get(j, 'fullName'),
  firstName: _get(j, 'firstName'),
  customerNumber: _get(j, 'customerNumber'),
  email: _opt<String>(j, 'email') ?? '',
  phone: _opt<String>(j, 'phone') ?? '',
);

BankAccount accountFromJson(Json j) => BankAccount(
  id: _get(j, 'id'),
  type: _enum(AccountType.values, j, 'type', aliases: {'fixed_deposit': AccountType.fixedDeposit, 'foreign_currency': AccountType.foreignCurrency}),
  name: _get(j, 'name'),
  maskedNumber: _get(j, 'maskedNumber'),
  balance: _money(j, 'balanceMinor'),
  currency: _opt<String>(j, 'currency') ?? 'LKR',
  active: _opt<bool>(j, 'active') ?? true,
  interestRate: _opt<num>(j, 'interestRate')?.toDouble(),
  maturityDate: _opt<String>(j, 'maturityDate') == null ? null : _date(j, 'maturityDate'),
);

BankCard cardFromJson(Json j) => BankCard(
  id: _get(j, 'id'),
  kind: _enum(CardKind.values, j, 'kind'),
  network: _enum(CardNetwork.values, j, 'network'),
  holder: _get(j, 'holder'),
  last4: _get(j, 'last4'),
  expiry: _get(j, 'expiry'),
  frozen: _opt<bool>(j, 'frozen') ?? false,
  blocked: _opt<bool>(j, 'blocked') ?? false,
  issuance: _opt<String>(j, 'issuance') == null
      ? CardIssuance.active
      : _enum(CardIssuance.values, j, 'issuance', aliases: {'pending_approval': CardIssuance.pendingApproval, 'ready_to_collect': CardIssuance.readyToCollect}),
  readyOn: _opt<String>(j, 'readyOn') == null ? null : _date(j, 'readyOn'),
  collectionBranch: _opt<String>(j, 'collectionBranch'),
);

CardControls cardControlsFromJson(Json j) => CardControls(
  dailyLimit: _money(j, 'dailyLimitMinor'),
  maxDailyLimit: _money(j, 'maxDailyLimitMinor'),
  onlineEnabled: _opt<bool>(j, 'onlineEnabled') ?? true,
  internationalEnabled: _opt<bool>(j, 'internationalEnabled') ?? false,
);

Json cardControlsToJson(CardControls c) => {
  'dailyLimitMinor': toMinor(c.dailyLimit),
  'onlineEnabled': c.onlineEnabled,
  'internationalEnabled': c.internationalEnabled,
};

Transaction transactionFromJson(Json j) => Transaction(
  id: _get(j, 'id'),
  merchant: _get(j, 'merchant'),
  category: _opt<String>(j, 'category') == null ? TxCategory.other : _enum(TxCategory.values, j, 'category'),
  amount: _money(j, 'amountMinor'),
  date: _date(j, 'date'),
  status: _opt<String>(j, 'status') == null ? TxStatus.completed : _enum(TxStatus.values, j, 'status'),
  accountId: _get(j, 'accountId'),
  reference: _opt<String>(j, 'reference') ?? '',
  method: _opt<String>(j, 'method') ?? '',
  internal: _opt<bool>(j, 'internal') ?? false,
);

Beneficiary beneficiaryFromJson(Json j) => Beneficiary(
  id: _get(j, 'id'),
  bank: _get(j, 'bank'),
  accountNumber: _get(j, 'accountNumber'),
  name: _get(j, 'name'),
  nickname: _opt<String>(j, 'nickname') ?? '',
  favorite: _opt<bool>(j, 'favorite') ?? false,
);

Json beneficiaryToJson(Beneficiary b) => {
  'bank': b.bank,
  'accountNumber': b.accountNumber,
  'name': b.name,
  'nickname': b.nickname,
  'favorite': b.favorite,
};

/// What the server needs to decide a payment. The fee is deliberately absent:
/// the server prices the payment and returns the authoritative fee on the receipt.
Json paymentToJson(PaymentDraft d) => {
  'kind': d.kind.name,
  'fromAccountId': d.fromAccountId,
  'toAccountId': d.toAccountId,
  'payee': d.payee,
  'payeeDetail': d.payeeDetail,
  'amountMinor': toMinor(d.amount),
  'reference': d.reference,
  'category': d.category.name,
  'loanId': d.loanId,
  'recurrence': d.recurrence.name,
  'scheduledFor': d.scheduledFor?.toUtc().toIso8601String(),
  'details': [
    for (final (label, value) in d.details) {'label': label, 'value': value},
  ],
};

ScheduledPayment scheduledPaymentFromJson(Json j) => ScheduledPayment(
  id: _get(j, 'id'),
  kind: _enum(PaymentKind.values, j, 'kind', aliases: _legacyKinds),
  fromAccountId: _get(j, 'fromAccountId'),
  payee: _get(j, 'payee'),
  payeeDetail: _opt<String>(j, 'payeeDetail') ?? '',
  amount: _money(j, 'amountMinor'),
  fee: _opt<num>(j, 'feeMinor') == null ? 0 : _money(j, 'feeMinor'),
  reference: _opt<String>(j, 'reference') ?? '',
  nextRun: _date(j, 'nextRun'),
  recurrence: _enum(Recurrence.values, j, 'recurrence'),
  status: _enum(ScheduleStatus.values, j, 'status'),
  runCount: _opt<num>(j, 'runCount')?.toInt() ?? 0,
  lastMessage: _opt<String>(j, 'lastMessage'),
);

Loan loanFromJson(Json j) => Loan(
  id: _get(j, 'id'),
  type: _enum(LoanType.values, j, 'type'),
  principal: _money(j, 'principalMinor'),
  outstanding: _money(j, 'outstandingMinor'),
  annualRate: _get<num>(j, 'annualRate').toDouble(),
  monthlyPayment: _money(j, 'monthlyPaymentMinor'),
  nextPaymentDate: _date(j, 'nextPaymentDate'),
  remainingMonths: _get<num>(j, 'remainingMonths').toInt(),
  totalMonths: _get<num>(j, 'totalMonths').toInt(),
  history: [
    for (final h in _opt<List<dynamic>>(j, 'history') ?? const [])
      if (h is Json) (date: _date(h, 'date'), amount: _money(h, 'amountMinor')) else throw _bad('history'),
  ],
);

Receipt receiptFromJson(Json j) => Receipt(
  id: _get(j, 'id'),
  kind: _enum(PaymentKind.values, j, 'kind', aliases: _legacyKinds),
  status: _enum(TxStatus.values, j, 'status'),
  payee: _get(j, 'payee'),
  amount: _money(j, 'amountMinor'),
  fee: _opt<num>(j, 'feeMinor') == null ? 0 : _money(j, 'feeMinor'),
  fromName: _get(j, 'fromName'),
  fromMasked: _get(j, 'fromMasked'),
  reference: _opt<String>(j, 'reference') ?? '',
  date: _date(j, 'date'),
  scheduled: _opt<bool>(j, 'scheduled') ?? false,
  details: [
    for (final d in _opt<List<dynamic>>(j, 'details') ?? const [])
      if (d is Json) (_get<String>(d, 'label'), _get<String>(d, 'value')) else throw _bad('details'),
  ],
);

/// Business reasons the server may refuse a payment, mapped to the failures the UI already handles.
PaymentFailure paymentFailureFor(String code) => switch (code) {
  'insufficient_funds' => PaymentFailure.insufficientFunds,
  'invalid_recipient' => PaymentFailure.invalidRecipient,
  'limit_exceeded' => PaymentFailure.limitExceeded,
  _ => PaymentFailure.unavailable,
};

SavingsGoal goalFromJson(Json j) => SavingsGoal(
  id: _get(j, 'id'),
  name: _get(j, 'name'),
  target: _money(j, 'targetMinor'),
  saved: _money(j, 'savedMinor'),
  targetDate: _date(j, 'targetDate'),
  autoMonthly: _opt<num>(j, 'autoMonthlyMinor') == null ? null : _money(j, 'autoMonthlyMinor'),
);

Json goalToJson(SavingsGoal g) => {
  'name': g.name,
  'targetMinor': toMinor(g.target),
  'targetDate': g.targetDate.toUtc().toIso8601String(),
  'autoMonthlyMinor': g.autoMonthly == null ? null : toMinor(g.autoMonthly!),
};

AppNotification notificationFromJson(Json j) => AppNotification(
  id: _get(j, 'id'),
  category: _enum(NotifCategory.values, j, 'category', aliases: {'bank_notices': NotifCategory.bankNotices}),
  title: _get(j, 'title'),
  body: _get(j, 'body'),
  date: _date(j, 'date'),
  read: _opt<bool>(j, 'read') ?? false,
  severity: _opt<String>(j, 'severity') == null ? Severity.info : _enum(Severity.values, j, 'severity'),
);

Json notificationToJson(AppNotification n) => {
  'category': n.category.name,
  'title': n.title,
  'body': n.body,
  'date': n.date.toUtc().toIso8601String(),
  'severity': n.severity.name,
};

DeviceSession sessionFromJson(Json j) => DeviceSession(
  id: _get(j, 'id'),
  name: _get(j, 'name'),
  platform: _get(j, 'platform'),
  lastActive: _date(j, 'lastActive'),
  approxLocation: _opt<String>(j, 'approxLocation') ?? '',
  current: _opt<bool>(j, 'current') ?? false,
);

LoginEvent loginEventFromJson(Json j) => LoginEvent(
  date: _date(j, 'date'),
  device: _get(j, 'device'),
  success: _get(j, 'success'),
  approxLocation: _opt<String>(j, 'approxLocation') ?? '',
);

TransferLimits transferLimitsFromJson(Json j) => TransferLimits(bankMaximum: _money(j, 'bankMaximumMinor'), daily: _money(j, 'dailyMinor'));

SupportBranch branchFromJson(Json j) => SupportBranch(
  name: _get(j, 'name'),
  address: _get(j, 'address'),
  distanceKm: _get<num>(j, 'distanceKm').toDouble(),
  isAtm: _opt<bool>(j, 'isAtm') ?? false,
  latitude: _opt<num>(j, 'latitude')?.toDouble(),
  longitude: _opt<num>(j, 'longitude')?.toDouble(),
);

Dispute disputeFromJson(Json j) => Dispute(
  id: _get(j, 'id'),
  transactionId: _get(j, 'transactionId'),
  merchant: _get(j, 'merchant'),
  amount: _money(j, 'amountMinor'),
  reason: _enum(DisputeReason.values, j, 'reason'),
  details: _opt<String>(j, 'details') ?? '',
  createdAt: _date(j, 'createdAt'),
);

LoanApplication loanApplicationFromJson(Json j) => LoanApplication(
  id: _get(j, 'id'),
  type: _enum(LoanType.values, j, 'type'),
  amount: _money(j, 'amountMinor'),
  termMonths: _get<num>(j, 'termMonths').toInt(),
  monthlyIncome: _money(j, 'monthlyIncomeMinor'),
  employment: _opt<String>(j, 'employment') ?? '',
  purpose: _opt<String>(j, 'purpose') ?? '',
  createdAt: _date(j, 'createdAt'),
  indicativeMonthly: _opt<num>(j, 'indicativeMonthlyMinor') == null ? 0 : _money(j, 'indicativeMonthlyMinor'),
);

FixedDeposit fixedDepositFromJson(Json j) => FixedDeposit(
  id: _get(j, 'id'),
  name: _opt<String>(j, 'name') ?? 'Fixed Deposit',
  maskedNumber: _get(j, 'maskedNumber'),
  principal: _money(j, 'principalMinor'),
  rate: _get<num>(j, 'rate').toDouble(),
  termMonths: _get<num>(j, 'termMonths').toInt(),
  startDate: _date(j, 'startDate'),
  maturityDate: _date(j, 'maturityDate'),
  renewal: _enum(FdRenewal.values, j, 'renewal'),
  fundingAccountId: _get(j, 'fundingAccountId'),
  status: _opt<String>(j, 'status') == null ? FdStatus.active : _enum(FdStatus.values, j, 'status'),
  renewals: _opt<num>(j, 'renewals')?.toInt() ?? 0,
  paidOut: _opt<num>(j, 'paidOutMinor') == null ? 0 : _money(j, 'paidOutMinor'),
);
