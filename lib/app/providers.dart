import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/device/device_services.dart';
import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../core/network/api_exceptions.dart';
import '../core/network/connectivity_service.dart';
import '../core/network/service_status.dart';
import '../core/network/token_authority.dart';
import '../core/security/biometric_service.dart';
import '../core/storage/preferences_store.dart';
import '../core/widgets/qr_scanner_view.dart';
import '../core/security/secure_store.dart';
import '../core/security/session_store.dart';
import '../features/authentication/data/api_auth_repository.dart';
import '../features/authentication/data/mock_auth_repository.dart';
import '../features/authentication/domain/auth_repository.dart';
import '../features/authentication/domain/identity_verification_service.dart';
import '../features/dashboard/data/api_banking_repositories.dart';
import '../features/dashboard/data/mock_banking_repositories.dart';
import '../features/dashboard/domain/banking_repositories.dart';
import '../features/payments/data/api_payment_repositories.dart';
import '../features/payments/data/local_receipt_service.dart';
import '../features/savings/data/mock_phase5_repositories.dart';
import '../features/savings/data/api_savings_repository.dart';
import '../features/security/data/api_engagement_repositories.dart';
import '../features/security/data/mock_engagement_repositories.dart';
import '../features/security/domain/engagement_repositories.dart';
import '../features/savings/domain/phase5_repositories.dart';
import '../features/statements/domain/statement_pdf.dart';
import '../features/transactions/domain/transaction_filter.dart';
import '../features/payments/data/mock_bank.dart';
import '../features/payments/data/mock_ledger.dart';
import '../features/payments/domain/payment_repositories.dart';
import '../shared/models/engagement_models.dart';
import '../shared/models/models.dart';
import '../shared/models/payment_models.dart';
import '../shared/models/service_models.dart';
import '../features/analytics/data/budget_repositories.dart';
import '../features/fixed_deposits/data/fixed_deposit_repositories.dart';
import '../features/fixed_deposits/domain/fixed_deposit.dart';
import '../features/analytics/domain/budgets.dart';
import '../features/transactions/data/api_dispute_repository.dart';
import '../features/transactions/data/mock_dispute_repository.dart';
import '../features/transactions/domain/dispute_repository.dart';

// Repositories and services: override these in `ProviderScope` to switch implementations.
//
// With no `--dart-define=API_BASE_URL=…` the app runs entirely on in-memory mocks. With one, the
// repositories listed in `docs/api_contract.md` (auth, accounts, cards, transactions, payments,
// beneficiaries, loans, savings goals, notifications, the security centre, limits and branch list)
// talk to that server. Support chat/FAQs and the identity-verification step stay local.
final apiConfigProvider = Provider<ApiConfig?>((_) => ApiConfig.fromEnvironment());

final tokenAuthorityProvider = Provider<SessionTokenAuthority?>((ref) {
  final config = ref.watch(apiConfigProvider);
  return config == null ? null : SessionTokenAuthority(ref.watch(sessionStoreProvider), ApiClient.bare(config));
});

/// Null in mock mode.
final apiClientProvider = Provider<ApiClient?>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokens = ref.watch(tokenAuthorityProvider);
  if (config == null || tokens == null) return null;
  return ApiClient(
    config: config,
    tokens: tokens,
    onSessionExpired: () => ref.read(authProvider.notifier).expireSession(),
    onMaintenance: (e) => ref.read(serviceStatusProvider.notifier).enterMaintenance(e),
    // Bodies are redacted by LogSanitizer, and nothing at all is logged in release builds.
    log: kDebugMode ? debugPrint : null,
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? MockAuthRepository() : ApiAuthRepository(api, ref.watch(tokenAuthorityProvider)!);
});
/// Counts times the mock bank added to the inbox on its own, so the notifications list knows to reload.
class InboxTickController extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final inboxTickProvider = NotifierProvider<InboxTickController, int>(InboxTickController.new);

/// The prototype's core bank. Each customer gets their own data; see [MockBank].
final mockBankProvider = Provider<MockBank>((_) => MockBank());
final customerDataProvider = Provider<MockCustomerData>((ref) {
  // Keyed by customer id, so editing a phone number doesn't rebuild the data or count as a new sign-in.
  final id = ref.watch(sessionScopeProvider);
  final user = ref.read(currentUserProvider);
  final data = ref.watch(mockBankProvider).forUser(id == null ? null : user);
  // Evaluated once per change of signed-in customer, so this is "a sign-in happened". It lives here, not in
  // AuthController, because a notifier may not read providers that depend on it. A real server logs sign-ins itself.
  if (id != null) data.security.recordSignIn(success: true);
  // The mock bank can drop something in the inbox by itself (a card is ready); tell the inbox to reload.
  data.onInboxChanged = () => Future.microtask(() {
    if (ref.mounted) ref.read(inboxTickProvider.notifier).bump();
  });
  ref.onDispose(() => data.onInboxChanged = null);
  return data;
});
final ledgerProvider = Provider<MockLedger>((ref) => ref.watch(customerDataProvider).ledger);
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockAccountRepository(ref.watch(ledgerProvider)) : ApiAccountRepository(api);
});
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? ref.watch(customerDataProvider).cards : ApiCardRepository(api);
});
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockTransactionRepository(ref.watch(ledgerProvider)) : ApiTransactionRepository(api);
});
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockPaymentRepository(ref.watch(ledgerProvider)) : ApiPaymentRepository(api);
});
final fixedDepositRepositoryProvider = Provider<FixedDepositRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockFixedDepositRepository(ref.watch(ledgerProvider)) : ApiFixedDepositRepository(api);
});

final fixedDepositsProvider = FutureProvider.autoDispose<List<FixedDeposit>>((ref) => ref.watch(fixedDepositRepositoryProvider).deposits());

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockBudgetRepository(ref.watch(ledgerProvider)) : ApiBudgetRepository(api);
});

final budgetsProvider = FutureProvider.autoDispose<List<Budget>>((ref) => ref.watch(budgetRepositoryProvider).budgets());

final disputeRepositoryProvider = Provider<DisputeRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockDisputeRepository(ref.watch(ledgerProvider)) : ApiDisputeRepository(api);
});

final disputesProvider = FutureProvider.autoDispose<List<Dispute>>((ref) => ref.watch(disputeRepositoryProvider).disputes());

final loanApplicationsProvider = FutureProvider.autoDispose<List<LoanApplication>>((ref) => ref.watch(loanRepositoryProvider).applications());

final scheduledPaymentRepositoryProvider = Provider<ScheduledPaymentRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockScheduledPaymentRepository(ref.watch(ledgerProvider)) : ApiScheduledPaymentRepository(api);
});

/// Scheduled and repeating payments, active ones first.
final scheduledPaymentsProvider = FutureProvider.autoDispose<List<ScheduledPayment>>(
  (ref) => ref.watch(scheduledPaymentRepositoryProvider).scheduled(),
);

final beneficiaryRepositoryProvider = Provider<BeneficiaryRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? ref.watch(customerDataProvider).beneficiaries : ApiBeneficiaryRepository(api);
});
final receiptServiceProvider = Provider<ReceiptService>((_) => const LocalReceiptService());
final identityServiceProvider = Provider<IdentityVerificationService>((_) => const MockIdentityVerificationService());
final secureStoreProvider = Provider<SecureStore>((_) => const FlutterSecureStore());
final locationServiceProvider = Provider<LocationService>((_) => const GeolocatorLocationService());
final qrScannerBuilderProvider = Provider<QrScannerBuilder>((_) => cameraQrScanner);
final connectivityServiceProvider = Provider<ConnectivityService>((_) => PlatformConnectivityService());
final healthCheckProvider = Provider<HealthCheck>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? const AlwaysUpHealthCheck() : ApiHealthCheck(api);
});
final biometricServiceProvider = Provider<BiometricService>((_) => LocalAuthBiometricService());
/// Mirrors who is signed in, for the providers that hold that customer's data.
///
/// It exists because Riverpod forbids a notifier from reading or invalidating providers that depend on
/// it. Data providers depend on this mirror instead of on [authProvider], so [AuthController] stays free to
/// reset them, and they reload by themselves whenever the signed-in customer changes.
class CurrentUserController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;
  void set(AppUser? user) => state = user;
}

final currentUserProvider = NotifierProvider<CurrentUserController, AppUser?>(CurrentUserController.new);

/// Changes whenever a different customer signs in or out. Watch it to scope data to the customer.
final sessionScopeProvider = Provider<String?>((ref) => ref.watch(currentUserProvider)?.id);

/// Overridden in `main()` with the preferences loaded from disk before the first frame.
final preferencesStoreProvider = Provider<PreferencesStore>((ref) => PreferencesStore(ref.watch(secureStoreProvider)));
final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore(ref.watch(secureStoreProvider)));

/// The signed-in user, or null when signed out.
class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  void _set(AppUser? user) {
    state = user;
    ref.read(currentUserProvider.notifier).set(user);
  }

  void start(AppUser user) => _set(user);

  /// The same customer with changed details (for example a new phone number).
  void updateUser(AppUser user) {
    if (state?.id != user.id) return;
    _set(user);
  }

  /// Signs in and persists a refresh token so the user can unlock with a PIN next time.
  /// The router then sends them to PIN setup.
  Future<void> startAndRemember(AppUser user) async {
    final token = await ref.read(authRepositoryProvider).issueRefreshToken(user);
    await ref.read(sessionStoreProvider).saveRefreshToken(token);
    ref.read(pinSetupPendingProvider.notifier).set(true);
    _set(user);
  }

  /// The server rejected our credentials and renewing them failed. Ends the session without
  /// calling the server again (it already said no) and leaves a note for the sign-in screen.
  Future<void> expireSession() async {
    if (state == null) return;
    ref.read(authNoticeProvider.notifier).set('Your session expired, so we signed you out to keep your money safe. Please sign in again.');
    await signOut(remote: false);
  }

  Future<void> signOut({bool remote = true}) async {
    if (remote) await ref.read(authRepositoryProvider).signOut();
    ref.read(tokenAuthorityProvider)?.clear();
    await ref.read(sessionStoreProvider).clear();
    // Drop every piece of user data held in memory.
    ref.invalidate(accountsProvider);
    ref.invalidate(cardsProvider);
    ref.invalidate(cardRepositoryProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(balanceVisibleProvider);
    ref.invalidate(securityProvider);
    ref.invalidate(ledgerProvider);
    ref.invalidate(beneficiaryRepositoryProvider);
    ref.invalidate(beneficiariesProvider);
    ref.invalidate(paymentDraftProvider);
    ref.invalidate(goalsProvider);
    ref.invalidate(loansProvider);
    ref.invalidate(notificationRepositoryProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(securityRepositoryProvider);
    // Theme, motion and lock timeout belong to the device; the default account and muted categories to the customer.
    await ref.read(preferencesStoreProvider).clearAccountData();
    ref.invalidate(settingsProvider);
    ref.read(appLockProvider.notifier).unlock();
    ref.invalidate(transactionFilterProvider);
    ref.read(pinSetupPendingProvider.notifier).set(false);
    _set(null);
  }
}

final authProvider = NotifierProvider<AuthController, AppUser?>(AuthController.new);

/// A one-off message for the sign-in screen, e.g. why the session ended.
class AuthNoticeController extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? message) => state = message;
}

final authNoticeProvider = NotifierProvider<AuthNoticeController, String?>(AuthNoticeController.new);

/// Whether the device has a network connection. Payments pause while it is false; when the
/// connection returns, on-screen data is refetched so nothing stays stale.
class OnlineController extends Notifier<bool> {
  @override
  bool build() {
    final service = ref.watch(connectivityServiceProvider);
    final sub = service.onlineChanges.listen(_set);
    ref.onDispose(sub.cancel);
    service.isOnline().then(_set);
    return true;
  }

  void _set(bool online) {
    if (!ref.mounted || online == state) return;
    state = online;
    if (online && ref.read(authProvider) != null) {
      ref.invalidate(accountsProvider);
      ref.invalidate(cardsProvider);
      ref.invalidate(transactionsProvider);
    }
  }
}

final onlineProvider = NotifierProvider<OnlineController, bool>(OnlineController.new);

class ServiceStatusController extends Notifier<ServiceStatus> {
  @override
  ServiceStatus build() => ServiceStatus.normal;

  void enterMaintenance(MaintenanceException e) => state = ServiceStatus(maintenance: true, message: e.message, retryAfter: e.retryAfter);

  /// Returns whether the bank is back; if so the maintenance screen goes away and data reloads.
  Future<bool> retry() async {
    final up = await ref.read(healthCheckProvider).isUp();
    if (up && ref.mounted) {
      state = ServiceStatus.normal;
      ref.invalidate(accountsProvider);
      ref.invalidate(cardsProvider);
      ref.invalidate(transactionsProvider);
    }
    return up;
  }
}

final serviceStatusProvider = NotifierProvider<ServiceStatusController, ServiceStatus>(ServiceStatusController.new);

/// True between signing in with "remember me" and finishing (or skipping) PIN setup.
class PinSetupPendingController extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final pinSetupPendingProvider = NotifierProvider<PinSetupPendingController, bool>(PinSetupPendingController.new);

@immutable
class SecuritySettings {
  const SecuritySettings({required this.hasPin, required this.biometricAvailable, required this.biometricEnabled});
  final bool hasPin, biometricAvailable, biometricEnabled;
}

class SecurityController extends AsyncNotifier<SecuritySettings> {
  @override
  Future<SecuritySettings> build() async {
    final store = ref.watch(sessionStoreProvider);
    final available = await ref.watch(biometricServiceProvider).isAvailable();
    return SecuritySettings(
      hasPin: await store.hasPin(),
      biometricAvailable: available,
      biometricEnabled: available && await store.biometricEnabled(),
    );
  }

  /// Turning on requires a successful biometric prompt. Returns whether the setting changed.
  Future<bool> setBiometric(bool on, {required String reason}) async {
    if (on && !await ref.read(biometricServiceProvider).authenticate(reason)) return false;
    await ref.read(sessionStoreProvider).setBiometricEnabled(on);
    ref.invalidateSelf();
    return true;
  }
}

final securityProvider = AsyncNotifierProvider<SecurityController, SecuritySettings>(SecurityController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(preferencesStoreProvider).current.themeMode;
  void set(ThemeMode mode) {
    state = mode;
    ref.read(preferencesStoreProvider).update((p) => p.copyWith(themeMode: mode));
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Whether balances are shown. Lives for the active session only.
class BalanceVisibleController extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() => state = !state;
}

final balanceVisibleProvider = NotifierProvider<BalanceVisibleController, bool>(BalanceVisibleController.new);

class OnboardingSeenController extends Notifier<bool> {
  @override
  bool build() => false;
  void markSeen() => state = true;
}

final onboardingSeenProvider = NotifierProvider<OnboardingSeenController, bool>(OnboardingSeenController.new);

final accountsProvider = FutureProvider<List<BankAccount>>(
  (ref) => ref.watch(accountRepositoryProvider).accounts(),
);

final transactionsProvider = FutureProvider<List<Transaction>>(
  (ref) => ref.watch(transactionRepositoryProvider).transactions(),
);

class CardsController extends AsyncNotifier<List<BankCard>> {
  @override
  Future<List<BankCard>> build() => ref.watch(cardRepositoryProvider).cards();

  /// Applies the change on screen straight away and rolls it back if the bank refuses it.
  /// Returns whether the change stuck.
  Future<bool> toggleFreeze(String id) async {
    final cards = state.value;
    if (cards == null) return false;
    final card = cards.firstWhere((c) => c.id == id);
    state = AsyncData([
      for (final c in cards) c.id == id ? c.copyWith(frozen: !c.frozen) : c,
    ]);
    try {
      await ref.read(cardRepositoryProvider).setFrozen(id, !card.frozen);
    } catch (_) {
      state = AsyncData(cards);
      return false;
    }
    ref.read(notificationsProvider.notifier).post(
      NotifCategory.security,
      card.frozen ? 'Card unfrozen' : 'Card frozen',
      card.frozen ? 'Your card ending ${card.last4} can be used again.' : 'Your card ending ${card.last4} is frozen. Payments are blocked.',
      severity: card.frozen ? Severity.info : Severity.warning,
    );
    return true;
  }
}

final cardsProvider = AsyncNotifierProvider<CardsController, List<BankCard>>(CardsController.new);

final cardControlsProvider = FutureProvider.autoDispose.family<CardControls, String>(
  (ref, cardId) => ref.watch(cardRepositoryProvider).controls(cardId),
);

/// The payment being composed, handed from an input screen to the confirm screen.
class PaymentDraftController extends Notifier<PaymentDraft?> {
  @override
  PaymentDraft? build() => null;
  void set(PaymentDraft? draft) => state = draft;
}

final paymentDraftProvider = NotifierProvider<PaymentDraftController, PaymentDraft?>(PaymentDraftController.new);

class BeneficiariesController extends AsyncNotifier<List<Beneficiary>> {
  BeneficiaryRepository get _repo => ref.read(beneficiaryRepositoryProvider);

  @override
  Future<List<Beneficiary>> build() async => _sorted(await ref.watch(beneficiaryRepositoryProvider).beneficiaries());

  /// Favourites first, then alphabetical.
  static List<Beneficiary> _sorted(List<Beneficiary> list) => [...list]
    ..sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

  Future<void> _refresh() async => state = AsyncData(_sorted(await _repo.beneficiaries()));

  Future<void> add(Beneficiary b) async {
    await _repo.add(b);
    ref.read(notificationsProvider.notifier).post(NotifCategory.security, 'New beneficiary added', '${b.name} (${b.bank}) was added to your beneficiaries.');
    await _refresh();
  }

  Future<void> edit(Beneficiary b) async {
    await _repo.update(b);
    await _refresh();
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    await _refresh();
  }
}

final beneficiariesProvider = AsyncNotifierProvider<BeneficiariesController, List<Beneficiary>>(BeneficiariesController.new);

final savingsRepositoryProvider = Provider<SavingsRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockSavingsRepository(ref.watch(ledgerProvider)) : ApiSavingsRepository(api);
});
final loanRepositoryProvider = Provider<LoanRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockLoanRepository(ref.watch(ledgerProvider)) : ApiLoanRepository(api);
});
final statementPdfBuilderProvider = Provider<StatementPdfBuilder>((_) => buildStatementPdf);
final statementExporterProvider = Provider<StatementExporter>((_) => const LocalStatementExporter());

class GoalsController extends AsyncNotifier<List<SavingsGoal>> {
  SavingsRepository get _repo => ref.read(savingsRepositoryProvider);

  @override
  Future<List<SavingsGoal>> build() => ref.watch(savingsRepositoryProvider).goals();

  Future<void> create(SavingsGoal goal) async {
    await _repo.create(goal);
    ref.invalidateSelf();
  }

  /// Positive deposits into the goal, negative withdraws. Throws `PaymentException` if refused.
  Future<void> move(String goalId, String accountId, double amount) async {
    await _repo.move(goalId, accountId, amount);
    ref.invalidate(accountsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidateSelf();
  }
}

final goalsProvider = AsyncNotifierProvider<GoalsController, List<SavingsGoal>>(GoalsController.new);

final loansProvider = FutureProvider<List<Loan>>((ref) => ref.watch(loanRepositoryProvider).loans());

class TransactionFilterController extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();
  void setQuery(String q) => state = state.copyWith(query: q);
  void set(TransactionFilter f) => state = f;
  void clearFilters() => state = state.withFilters();
}

final transactionFilterProvider = NotifierProvider<TransactionFilterController, TransactionFilter>(TransactionFilterController.new);

final filteredTransactionsProvider = Provider<AsyncValue<List<Transaction>>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  return ref.watch(transactionsProvider).whenData((all) => all.where(filter.matches).toList());
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? ref.watch(customerDataProvider).notifications : ApiNotificationRepository(api);
});
final securityRepositoryProvider = Provider<SecurityRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? ref.watch(customerDataProvider).security : ApiSecurityRepository(api);
});
final limitsRepositoryProvider = Provider<LimitsRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockLimitsRepository(ref.watch(ledgerProvider)) : ApiLimitsRepository(api);
});
final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  ref.watch(sessionScopeProvider);
  final api = ref.watch(apiClientProvider);
  return api == null ? MockSupportRepository() : ApiSupportRepository(api);
});
final linkLauncherProvider = Provider<LinkLauncher>((_) => const UrlLinkLauncher());

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  NotificationRepository get _repo => ref.read(notificationRepositoryProvider);

  @override
  Future<List<AppNotification>> build() {
    ref.watch(inboxTickProvider); // reload when the mock bank adds something itself
    return ref.watch(notificationRepositoryProvider).notifications();
  }

  Future<void> markRead(String id) async {
    await _repo.markRead(id);
    ref.invalidateSelf();
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead();
    ref.invalidateSelf();
  }

  /// Records something that just happened (a payment, a card freeze, a PIN change…).
  Future<void> post(NotifCategory category, String title, String body, {Severity severity = Severity.info}) async {
    if (category != NotifCategory.security && ref.read(settingsProvider).mutedCategories.contains(category)) return;
    await _repo.add(
      AppNotification(
        id: 'n-${DateTime.now().microsecondsSinceEpoch}',
        category: category,
        title: title,
        body: body,
        date: DateTime.now(),
        severity: severity,
      ),
    );
    ref.invalidateSelf();
  }
}

final notificationsProvider = AsyncNotifierProvider<NotificationsController, List<AppNotification>>(NotificationsController.new);

final unreadCountProvider = Provider<int>((ref) => ref.watch(notificationsProvider).value?.where((n) => !n.read).length ?? 0);

final sessionsProvider = FutureProvider.autoDispose<List<DeviceSession>>((ref) => ref.watch(securityRepositoryProvider).sessions());
final loginHistoryProvider = FutureProvider.autoDispose<List<LoginEvent>>((ref) => ref.watch(securityRepositoryProvider).loginHistory());
final twoFactorProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(securityRepositoryProvider).twoFactorEnabled());
final limitsProvider = FutureProvider.autoDispose<TransferLimits>((ref) => ref.watch(limitsRepositoryProvider).limits());
final branchesProvider = FutureProvider.autoDispose<List<SupportBranch>>((ref) => ref.watch(supportRepositoryProvider).nearby());

@immutable
class AppSettings {
  const AppSettings({this.reduceMotion = false, this.defaultAccountId, this.mutedCategories = const {}});
  final bool reduceMotion;
  final String? defaultAccountId;

  /// Categories the user turned notifications off for.
  final Set<NotifCategory> mutedCategories;

  AppSettings copyWith({bool? reduceMotion, String? defaultAccountId, Set<NotifCategory>? mutedCategories}) => AppSettings(
    reduceMotion: reduceMotion ?? this.reduceMotion,
    defaultAccountId: defaultAccountId ?? this.defaultAccountId,
    mutedCategories: mutedCategories ?? this.mutedCategories,
  );
}

class SettingsController extends Notifier<AppSettings> {
  PreferencesStore get _prefs => ref.read(preferencesStoreProvider);

  @override
  AppSettings build() {
    final p = _prefs.current;
    return AppSettings(
      reduceMotion: p.reduceMotion,
      defaultAccountId: p.defaultAccountId,
      mutedCategories: {
        for (final c in NotifCategory.values)
          if (p.mutedCategories.contains(c.name)) c,
      },
    );
  }

  void setReduceMotion(bool v) {
    state = state.copyWith(reduceMotion: v);
    _prefs.update((p) => p.copyWith(reduceMotion: v));
  }

  void setDefaultAccount(String id) {
    state = state.copyWith(defaultAccountId: id);
    _prefs.update((p) => p.copyWith(defaultAccountId: id));
  }

  void setMuted(NotifCategory c, {required bool muted}) {
    state = state.copyWith(mutedCategories: muted ? {...state.mutedCategories, c} : ({...state.mutedCategories}..remove(c)));
    _prefs.update((p) => p.copyWith(mutedCategories: {for (final m in state.mutedCategories) m.name}));
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// How long the app may sit idle or in the background before asking for the PIN again.
class LockTimeoutController extends Notifier<Duration> {
  @override
  Duration build() => Duration(seconds: ref.read(preferencesStoreProvider).current.lockTimeoutSeconds);
  void set(Duration d) {
    state = d;
    ref.read(preferencesStoreProvider).update((p) => p.copyWith(lockTimeoutSeconds: d.inSeconds));
  }
}

final lockTimeoutProvider = NotifierProvider<LockTimeoutController, Duration>(LockTimeoutController.new);

/// After this much total inactivity the session ends and the password is needed again.
const sessionTimeout = Duration(minutes: 30);

@immutable
class AppLockState {
  const AppLockState({this.locked = false, this.returnTo});
  final bool locked;
  final String? returnTo;
}

class AppLockController extends Notifier<AppLockState> {
  @override
  AppLockState build() => const AppLockState();
  void lock(String returnTo) => state = state.locked ? state : AppLockState(locked: true, returnTo: returnTo);
  void unlock() => state = const AppLockState();
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
