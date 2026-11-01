import 'dart:async';
import 'package:bank_app/app/app.dart';
import 'package:bank_app/app/providers.dart';
import 'package:bank_app/core/device/device_services.dart';
import 'package:bank_app/core/network/connectivity_service.dart';
import 'package:bank_app/core/network/service_status.dart';
import 'package:bank_app/core/security/biometric_service.dart';
import 'package:bank_app/core/security/secure_store.dart';
import 'package:bank_app/features/authentication/data/mock_auth_repository.dart';
import 'package:bank_app/features/authentication/domain/auth_repository.dart';
import 'package:bank_app/features/payments/domain/payment_repositories.dart';
import 'package:bank_app/features/savings/domain/phase5_repositories.dart';
import 'package:bank_app/features/security/domain/engagement_repositories.dart';
import 'package:bank_app/shared/models/payment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frames are advanced manually: splash, onboarding and skeletons animate forever,
/// so `pumpAndSettle` would never return.
Future<void> advance(WidgetTester tester, [int ms = 500]) => tester.pump(Duration(milliseconds: ms));

void useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The harness substitutes a fixed-width font; load the real one so layout checks are meaningful.
Future<void> loadAppFont() async {
  final loader = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
  await loader.load();
}

class FakeBiometrics implements BiometricService {
  FakeBiometrics({this.available = false, this.succeeds = true});
  final bool available, succeeds;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async => succeeds;
}

class FakeReceiptService implements ReceiptService {
  final shared = <Receipt>[];
  final saved = <Receipt>[];

  @override
  Future<void> share(Receipt receipt) async => shared.add(receipt);

  @override
  Future<String> save(Receipt receipt) async {
    saved.add(receipt);
    return '/fake/${receipt.id}.txt';
  }
}

class FakeStatementExporter implements StatementExporter {
  final shared = <(String, String)>[];
  final saved = <(String, String)>[];

  @override
  Future<void> shareCsv(String fileName, String csv) async => shared.add((fileName, csv));

  @override
  Future<String> saveCsv(String fileName, String csv) async {
    saved.add((fileName, csv));
    return '/fake/$fileName';
  }

  final pdfShared = <(String, int)>[];
  final pdfSaved = <(String, int)>[];

  @override
  Future<void> sharePdf(String fileName, Uint8List bytes) async => pdfShared.add((fileName, bytes.length));

  @override
  Future<String> savePdf(String fileName, Uint8List bytes) async {
    pdfSaved.add((fileName, bytes.length));
    return '/fake/$fileName';
  }
}

class FakeLinkLauncher implements LinkLauncher {
  FakeLinkLauncher({this.canOpen = true});
  final bool canOpen;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return canOpen;
  }
}

class FakeConnectivity implements ConnectivityService {
  FakeConnectivity({this.online = true});
  bool online;
  final _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onlineChanges => _changes.stream;

  void set(bool value) {
    online = value;
    _changes.add(value);
  }
}

class FakeLocation implements LocationService {
  FakeLocation([this.position]);
  GeoPoint? position;
  int asked = 0;

  @override
  Future<GeoPoint?> current() async {
    asked++;
    return position;
  }
}

/// Stands in for the camera: shows a plain box, and lets a test "scan" by calling [scan].
class FakeScanner {
  ValueChanged<String>? _onCode;
  int built = 0;

  Widget build(BuildContext context, ValueChanged<String> onCode) {
    built++;
    _onCode = onCode;
    return const ColoredBox(color: Colors.black12, child: Center(child: Text('Camera preview')));
  }

  void scan(String code) => _onCode!(code);
}

class FakeHealthCheck implements HealthCheck {
  FakeHealthCheck({this.up = false});
  bool up;
  int checks = 0;

  @override
  Future<bool> isUp() async {
    checks++;
    return up;
  }
}

/// Everything an app run shares; reuse one [TestEnv] to simulate relaunching the app.
class TestEnv {
  TestEnv({BiometricService? biometrics})
    : biometrics = biometrics ?? FakeBiometrics(),
      store = MemorySecureStore(),
      repo = MockAuthRepository(),
      receipts = FakeReceiptService(),
      statements = FakeStatementExporter(),
      links = FakeLinkLauncher(),
      connectivity = FakeConnectivity(),
      health = FakeHealthCheck(),
      location = FakeLocation(),
      scanner = FakeScanner();
  final MemorySecureStore store;
  final FakeConnectivity connectivity;
  final FakeHealthCheck health;
  final FakeLocation location;
  final FakeScanner scanner;
  final AuthRepository repo;
  final BiometricService biometrics;
  final FakeReceiptService receipts;
  final FakeStatementExporter statements;
  final FakeLinkLauncher links;

  Widget app() => ProviderScope(
    overrides: [
      secureStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(repo),
      biometricServiceProvider.overrideWithValue(biometrics),
      receiptServiceProvider.overrideWithValue(receipts),
      statementExporterProvider.overrideWithValue(statements),
      linkLauncherProvider.overrideWithValue(links),
      connectivityServiceProvider.overrideWithValue(connectivity),
      healthCheckProvider.overrideWithValue(health),
      locationServiceProvider.overrideWithValue(location),
      qrScannerBuilderProvider.overrideWithValue(scanner.build),
      statementPdfBuilderProvider.overrideWithValue(({required account, required month, required transactions, required customerName, required generatedAt}) async => Uint8List(2048)),
    ],
    child: const BankApp(),
  );

  /// Cold start: tears the old tree down, mounts a fresh one on the same storage.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await advance(tester, 100); // let the splash decide where to go
  }
}

/// Relaunches the app and waits out the shortened returning-user splash.
Future<void> relaunch(WidgetTester tester, TestEnv env) async {
  await env.launch(tester);
  await advance(tester, 1500);
  await advance(tester, 600);
}

Future<void> openLogin(WidgetTester tester, TestEnv env) async {
  await env.launch(tester);
  await advance(tester, 2300); // splash
  await advance(tester, 500);
  expect(find.text('Banking made effortless'), findsOneWidget);
  await tester.tap(find.text('Skip'));
  await advance(tester, 100);
  await advance(tester, 600);
  expect(find.text('Welcome back'), findsOneWidget);
}

Future<void> signIn(WidgetTester tester, {String user = MockAuthRepository.demoUsername, String password = MockAuthRepository.demoPassword, bool remember = false}) async {
  await tester.enterText(find.byKey(const ValueKey('identifier')), user);
  await tester.enterText(find.byKey(const ValueKey('password')), password);
  if (remember) await tester.tap(find.byType(Checkbox));
  await tester.tap(find.text('Sign In'));
  await advance(tester, 1000); // mock latency
  await advance(tester, 400); // card fades out
  await advance(tester, 700); // transition
}

Future<void> signInAsDemo(WidgetTester tester) async {
  await signIn(tester);
  await advance(tester, 1500); // data + count-up
}

Future<void> tapPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.text(d));
    await tester.pump(const Duration(milliseconds: 30));
  }
}
