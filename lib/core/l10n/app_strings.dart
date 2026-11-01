/// All user-visible copy lives here so it can be swapped for generated
/// localisation (English now; Sinhala and Tamil later) without touching widgets.
class AppStrings {
  const AppStrings._();

  static const bankName = 'Zentrix Bank';

  // Navigation
  static const navHome = 'Home';
  static const navPayments = 'Payments';
  static const navCards = 'Cards';
  static const navAnalytics = 'Analytics';
  static const navProfile = 'Profile';

  // Onboarding
  static const skip = 'Skip';
  static const next = 'Next';
  static const getStarted = 'Get Started';
  static const onboarding = [
    ('Banking made effortless', 'Manage your money securely, from one place, wherever you are.'),
    ('Everything in one place', 'Transfers, payments, cards and savings — all together.'),
    ('Secure by design', 'Device security, transaction verification and fraud monitoring protect every move.'),
  ];

  // Login
  static const welcomeBack = 'Welcome back';
  static const loginSubtitle = 'Sign in to your Zentrix account.';
  static const identifierLabel = 'Username, email or customer ID';
  static const passwordLabel = 'Password';
  static const rememberMe = 'Remember me';
  static const forgotPassword = 'Forgot password?';
  static const signIn = 'Sign In';
  static const newHere = 'New to Zentrix Bank?';
  static const createAccount = 'Create account';
  static const invalidCredentials = 'Incorrect username or password.';

  // Dashboard
  static const totalBalance = 'Total balance';
  static const quickActions = 'Quick actions';
  static const accounts = 'Accounts';
  static const recentTransactions = 'Recent transactions';
  static const viewAll = 'View all';
  static const noTransactions = 'No transactions yet';
  static const noTransactionsHint = 'Your latest activity will appear here.';

  // Profile
  static const logout = 'Log out';
  static const logoutConfirm = 'Are you sure you want to log out?';
}
