import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/authentication/presentation/login_page.dart';
import '../features/authentication/presentation/forgot_password_page.dart';
import '../features/authentication/presentation/pin_setup_page.dart';
import '../features/authentication/presentation/register/register_page.dart';
import '../features/authentication/presentation/unlock_page.dart';
import '../features/cards/presentation/card_management_pages.dart';
import '../features/cards/presentation/card_pin_page.dart';
import '../features/cards/presentation/cards_page.dart';
import '../features/dashboard/presentation/account_detail_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/dashboard/presentation/open_account_page.dart';
import '../features/fixed_deposits/presentation/fixed_deposits_page.dart';
import '../features/fixed_deposits/presentation/open_fixed_deposit_page.dart';
import '../features/loans/presentation/loan_application_page.dart';
import '../features/analytics/presentation/analytics_page.dart';
import '../features/analytics/presentation/budgets_page.dart';
import '../features/authentication/presentation/lock_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/search/search_page.dart';
import '../features/security/presentation/change_password_page.dart';
import '../features/profile/presentation/edit_profile_page.dart';
import '../features/security/presentation/change_pin_page.dart';
import '../features/security/presentation/devices_limits_history_pages.dart';
import '../features/security/presentation/security_center_page.dart';
import '../features/settings/settings_page.dart';
import '../features/support/presentation/support_pages.dart';
import '../features/loans/presentation/loans_page.dart';
import '../features/savings/presentation/savings_page.dart';
import '../features/statements/presentation/statements_page.dart';
import '../features/transactions/presentation/dispute_pages.dart';
import '../features/transactions/presentation/transaction_details_page.dart';
import '../features/transactions/presentation/transactions_page.dart';
import '../features/navigation/shell_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/payments/presentation/beneficiaries_page.dart';
import '../features/payments/presentation/bills_page.dart';
import '../features/payments/presentation/confirm_payment_page.dart';
import '../features/payments/presentation/payments_page.dart';
import '../features/payments/presentation/qr_page.dart';
import '../features/payments/presentation/scheduled_payments_page.dart';
import '../features/payments/presentation/transfer_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/splash/splash_page.dart';
import '../shared/models/engagement_models.dart';
import '../shared/models/models.dart';
import '../shared/models/payment_models.dart';
import 'providers.dart';
import 'transitions.dart';

const _publicRoutes = {'/splash', '/onboarding', '/login', '/register', '/forgot-password', '/unlock'};

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the session starts or ends.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.listen(pinSetupPendingProvider, (_, _) => refresh.value++);
  ref.listen(appLockProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  Page<void> tab(GoRouterState s, Widget child) => NoTransitionPage<void>(key: s.pageKey, child: child);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(authProvider) != null;
      final location = state.matchedLocation;
      final isPublic = _publicRoutes.contains(location);
      if (!signedIn) return isPublic ? null : '/login';
      if (ref.read(appLockProvider).locked) return location == '/lock' ? null : '/lock';
      if (ref.read(pinSetupPendingProvider)) return location == '/pin-setup' ? null : '/pin-setup';
      return (isPublic || location == '/pin-setup' || location == '/lock') ? '/home' : null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, s) => appPage(s, const SplashPage(), motion: PageMotion.fadeScale),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, s) => appPage(s, const OnboardingPage(), motion: PageMotion.fadeScale),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, s) => appPage(s, const LoginPage(), motion: PageMotion.fadeScale),
      ),
      GoRoute(path: '/register', pageBuilder: (_, s) => appPage(s, const RegisterPage())),
      GoRoute(path: '/forgot-password', pageBuilder: (_, s) => appPage(s, const ForgotPasswordPage())),
      GoRoute(
        path: '/unlock',
        pageBuilder: (_, s) => appPage(s, const UnlockPage(), motion: PageMotion.fadeScale),
      ),
      GoRoute(
        path: '/pin-setup',
        pageBuilder: (_, s) => appPage(s, const PinSetupPage(), motion: PageMotion.fadeScale),
      ),
      GoRoute(
        path: '/transfer',
        pageBuilder: (_, s) => appPage(s, TransferPage(preselected: s.extra as Beneficiary?, fromAccountId: s.uri.queryParameters['from'])),
      ),
      GoRoute(path: '/profile/edit', pageBuilder: (_, s) => appPage(s, const EditProfilePage())),
      GoRoute(path: '/budgets', pageBuilder: (_, s) => appPage(s, const BudgetsPage())),
      GoRoute(path: '/disputes', pageBuilder: (_, s) => appPage(s, const DisputesPage())),
      GoRoute(path: '/disputes/new', pageBuilder: (_, s) => appPage(s, DisputeFormPage(transactionId: s.uri.queryParameters['tx'] ?? ''))),
      GoRoute(path: '/scheduled', pageBuilder: (_, s) => appPage(s, const ScheduledPaymentsPage())),
      GoRoute(path: '/beneficiaries', pageBuilder: (_, s) => appPage(s, const BeneficiariesPage())),
      GoRoute(path: '/bills', pageBuilder: (_, s) => appPage(s, const BillsPage())),
      GoRoute(
        path: '/qr',
        pageBuilder: (_, s) => appPage(s, QrPage(showMyQr: s.uri.queryParameters['mine'] == '1')),
      ),
      GoRoute(path: '/transactions', pageBuilder: (_, s) => appPage(s, const TransactionsPage())),
      GoRoute(
        path: '/transactions/:id',
        pageBuilder: (_, s) => appPage(s, TransactionDetailsPage(id: s.pathParameters['id']!, initial: s.extra as Transaction?)),
      ),
      GoRoute(path: '/lock', pageBuilder: (_, s) => appPage(s, const LockPage(), motion: PageMotion.fadeScale)),
      GoRoute(
        path: '/notifications',
        pageBuilder: (_, s) => appPage(s, NotificationsPage(initial: s.extra as NotifCategory?)),
      ),
      GoRoute(path: '/search', pageBuilder: (_, s) => appPage(s, const SearchPage(), motion: PageMotion.fadeScale)),
      GoRoute(path: '/settings', pageBuilder: (_, s) => appPage(s, const SettingsPage())),
      GoRoute(path: '/cards/manage', pageBuilder: (_, s) => appPage(s, const CardManagementPage())),
      GoRoute(path: '/cards/manage/:id', pageBuilder: (_, s) => appPage(s, CardDetailPage(cardId: s.pathParameters['id']!))),
      GoRoute(path: '/cards/pin/:id', pageBuilder: (_, s) => appPage(s, CardPinPage(cardId: s.pathParameters['id']!))),
      GoRoute(path: '/security', pageBuilder: (_, s) => appPage(s, const SecurityCenterPage())),
      GoRoute(path: '/security/password', pageBuilder: (_, s) => appPage(s, const ChangePasswordPage())),
      GoRoute(path: '/security/pin', pageBuilder: (_, s) => appPage(s, const ChangePinPage())),
      GoRoute(path: '/security/devices', pageBuilder: (_, s) => appPage(s, const DevicesPage())),
      GoRoute(path: '/security/limits', pageBuilder: (_, s) => appPage(s, const LimitsPage())),
      GoRoute(path: '/security/history', pageBuilder: (_, s) => appPage(s, const LoginHistoryPage())),
      GoRoute(path: '/support', pageBuilder: (_, s) => appPage(s, const SupportPage())),
      GoRoute(path: '/support/chat', pageBuilder: (_, s) => appPage(s, const SupportChatPage())),
      GoRoute(path: '/support/branches', pageBuilder: (_, s) => appPage(s, const BranchesPage())),
      GoRoute(path: '/savings', pageBuilder: (_, s) => appPage(s, const SavingsPage())),
      GoRoute(path: '/loans', pageBuilder: (_, s) => appPage(s, const LoansPage())),
      GoRoute(path: '/loans/calculator', pageBuilder: (_, s) => appPage(s, const LoanCalculatorPage())),
      GoRoute(path: '/statements', pageBuilder: (_, s) => appPage(s, StatementsPage(accountId: s.uri.queryParameters['account']))),
      GoRoute(path: '/fixed-deposits', pageBuilder: (_, s) => appPage(s, const FixedDepositsPage())),
      GoRoute(path: '/fixed-deposits/open', pageBuilder: (_, s) => appPage(s, const OpenFixedDepositPage())),
      GoRoute(path: '/accounts/open', pageBuilder: (_, s) => appPage(s, const OpenAccountPage())),
      GoRoute(path: '/loans/apply', pageBuilder: (_, s) => appPage(s, const LoanApplicationPage())),
      GoRoute(path: '/accounts/:id', pageBuilder: (_, s) => appPage(s, AccountDetailPage(accountId: s.pathParameters['id']!))),
      GoRoute(path: '/pay/confirm', pageBuilder: (_, s) => appPage(s, const ConfirmPaymentPage())),
      StatefulShellRoute.indexedStack(
        pageBuilder: (_, s, shell) => appPage(s, ShellPage(shell: shell), motion: PageMotion.reveal),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', pageBuilder: (_, s) => tab(s, const DashboardPage()))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/payments', pageBuilder: (_, s) => tab(s, const PaymentsPage()))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/cards', pageBuilder: (_, s) => tab(s, const CardsPage()))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/analytics', pageBuilder: (_, s) => tab(s, const AnalyticsPage()))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', pageBuilder: (_, s) => tab(s, const ProfilePage()))],
          ),
        ],
      ),
    ],
  );
});
