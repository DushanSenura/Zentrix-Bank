import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_nav_bar.dart';

const _items = [
  NavItem(Icons.home_outlined, Icons.home_rounded, AppStrings.navHome),
  NavItem(Icons.swap_horiz_rounded, Icons.swap_horiz_rounded, AppStrings.navPayments),
  NavItem(Icons.credit_card_outlined, Icons.credit_card_rounded, AppStrings.navCards),
  NavItem(Icons.insights_outlined, Icons.insights_rounded, AppStrings.navAnalytics),
  NavItem(Icons.person_outline_rounded, Icons.person_rounded, AppStrings.navProfile),
];

/// Hosts the five primary tabs; `IndexedStack` (via the shell route) keeps each tab's state.
class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: shell,
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth - 32),
            child: GlassNavBar(
              items: _items,
              index: shell.currentIndex,
              onSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            ),
          ),
        ),
      ),
    ),
  );
}
