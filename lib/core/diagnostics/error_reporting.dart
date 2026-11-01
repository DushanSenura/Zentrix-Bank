import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Where unexpected errors go. The prototype only prints in debug builds; a production build
/// should forward to a crash service (Sentry, Crashlytics…) after removing personal data.
/// Reporters receive the error and stack only — never request bodies, tokens or form contents.
abstract interface class CrashReporter {
  void record(Object error, StackTrace? stack, {String? context});
}

class DebugCrashReporter implements CrashReporter {
  const DebugCrashReporter();

  @override
  void record(Object error, StackTrace? stack, {String? context}) {
    if (kDebugMode) debugPrint('Unhandled ${context ?? 'error'}: ${error.runtimeType}\n$stack');
  }
}

/// Routes framework errors and uncaught async errors to [reporter], and replaces Flutter's
/// red/grey error widget with a calm one in release builds so no exception text reaches a customer.
void installErrorHandling(CrashReporter reporter, {bool? release}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    reporter.record(details.exception, details.stack, context: 'framework');
    if (kDebugMode) previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reporter.record(error, stack, context: 'async');
    return true; // handled: do not crash the app
  };
  if (release ?? kReleaseMode) {
    ErrorWidget.builder = (details) => const _FriendlyError();
  }
}

class _FriendlyError extends StatelessWidget {
  const _FriendlyError();

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Something went wrong here. Please go back and try again.', textAlign: TextAlign.center),
      ),
    ),
  );
}
