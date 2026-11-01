import 'package:flutter/material.dart';
import '../network/api_exceptions.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'empty_state.dart';

/// What the customer is told when loading something failed. The wording depends on *why*:
/// offline, bank maintenance, expired session and server trouble each need different advice.
({IconData icon, String message}) describeFailure(Object error) => switch (error) {
  NetworkException() => (icon: Icons.wifi_off_rounded, message: 'Check your connection and try again.'),
  MaintenanceException e => (icon: Icons.construction_rounded, message: e.message),
  UnauthorizedException() => (icon: Icons.lock_clock_rounded, message: 'Your session has expired. Please sign in again.'),
  ServerException e => (icon: Icons.cloud_off_rounded, message: e.message),
  RejectedException e => (icon: Icons.info_outline_rounded, message: e.message),
  _ => (icon: Icons.cloud_off_rounded, message: 'Please try again.'),
};

/// Replaces a screen section whose data failed to load, with a retry that is always reachable.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.what, this.onRetry});
  final Object error;

  /// Lower-case noun for the title, e.g. "cards" → "Couldn’t load cards".
  final String what;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final d = describeFailure(error);
    final ref = error is ApiException ? (error as ApiException).requestId : null;
    final retryable = onRetry != null && error is! UnauthorizedException;
    return Semantics(
      liveRegion: true,
      child: EmptyState(
        icon: d.icon,
        title: 'Couldn’t load $what',
        message: d.message,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (retryable) TextButton(onPressed: onRetry, child: const Text('Retry')),
            if (ref != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Reference $ref', style: AppTypography.caption.copyWith(color: context.colors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}
