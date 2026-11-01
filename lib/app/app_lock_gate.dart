import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/bank_logo.dart';
import 'providers.dart';
import 'router.dart';

/// Wraps the whole app to (1) ask for the PIN again after inactivity or time in the background,
/// (2) end the session after a long absence, and (3) hide content from the app switcher.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  Timer? _idle;
  DateTime? _backgroundedAt;
  bool _shield = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    super.dispose();
  }

  bool get _signedIn => ref.read(authProvider) != null;

  void _touch() {
    _idle?.cancel();
    if (!_signedIn || ref.read(appLockProvider).locked) return;
    _idle = Timer(ref.read(lockTimeoutProvider), _lock);
  }

  /// Locks only when there is a PIN to unlock with; otherwise the idle timer has nothing to do.
  Future<void> _lock() async {
    if (!mounted || !_signedIn || ref.read(appLockProvider).locked) return;
    if (!await ref.read(sessionStoreProvider).hasPin() || !mounted) return;
    final where = ref.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();
    ref.read(appLockProvider.notifier).lock(where);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (state == AppLifecycleState.resumed) {
      setState(() => _shield = false);
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since == null || !_signedIn) return;
      final gone = DateTime.now().difference(since);
      if (gone >= sessionTimeout) {
        ref.read(authProvider.notifier).signOut();
      } else if (gone >= ref.read(lockTimeoutProvider)) {
        _lock();
      }
      _touch();
    } else {
      setState(() => _shield = true);
      if (away) {
        _backgroundedAt ??= DateTime.now();
        _idle?.cancel();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, _) => _touch());
    ref.listen(lockTimeoutProvider, (_, _) => _touch());
    ref.listen(appLockProvider, (_, s) {
      if (!s.locked) _touch();
    });
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_shield) const _PrivacyShield(),
        ],
      ),
    );
  }
}

class _PrivacyShield extends StatelessWidget {
  const _PrivacyShield();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ColoredBox(
      color: context.colors.background,
      child: const Center(child: BankLogo(size: 44)),
    ),
  );
}
