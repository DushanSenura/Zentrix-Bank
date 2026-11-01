import 'package:bank_app/core/diagnostics/error_reporting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder implements CrashReporter {
  final seen = <(Object, String?)>[];

  @override
  void record(Object error, StackTrace? stack, {String? context}) => seen.add((error, context));
}

void main() {
  test('framework and async errors reach the reporter, and uncaught async errors do not crash', () {
    final onError = FlutterError.onError;
    final platform = PlatformDispatcher.instance.onError;
    final builder = ErrorWidget.builder;
    addTearDown(() {
      FlutterError.onError = onError;
      PlatformDispatcher.instance.onError = platform;
      ErrorWidget.builder = builder;
    });

    final reporter = _Recorder();
    installErrorHandling(reporter, release: false);

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom')));
    expect(PlatformDispatcher.instance.onError!(ArgumentError('late'), StackTrace.empty), isTrue);

    expect(reporter.seen.map((e) => e.$2), ['framework', 'async']);
    expect(reporter.seen.first.$1, isA<StateError>());
  });

  testWidgets('release builds replace the error widget so no exception text is shown', (tester) async {
    final builder = ErrorWidget.builder;
    installErrorHandling(_Recorder(), release: true);
    try {
      await tester.pumpWidget(Builder(builder: (_) => ErrorWidget.builder(FlutterErrorDetails(exception: StateError('SECRET INTERNALS')))));
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.textContaining('Something went wrong here'), findsOneWidget);
    } finally {
      // flutter_test checks this invariant before tearDown callbacks run, so restore it here.
      ErrorWidget.builder = builder;
    }
  });
}
