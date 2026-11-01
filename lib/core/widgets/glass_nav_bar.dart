import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';

class NavItem {
  const NavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon, selectedIcon;
  final String label;
}

/// Floating liquid-glass tab bar with an animated selection pill.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.items, required this.index, required this.onSelected});
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  static const height = 68.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final duration = AppAnimations.scaled(context, AppAnimations.normal);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: AppRadius.pillAll, boxShadow: AppShadows.elevated),
      child: ClipRRect(
        borderRadius: AppRadius.pillAll,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: AppRadius.pillAll,
              color: c.glassFill,
              border: Border.all(color: c.glassBorder),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final itemWidth = box.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: duration,
                      curve: AppAnimations.standard,
                      left: itemWidth * index + 6,
                      top: 6,
                      width: itemWidth - 12,
                      height: height - 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.pillAll,
                          color: c.accent.withAlpha(36),
                          boxShadow: AppShadows.glow(c.accent),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: _NavButton(
                              item: items[i],
                              selected: i == index,
                              onTap: () {
                                if (i != index) HapticFeedback.selectionClick();
                                onSelected(i);
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.accent : c.textSecondary;
    final duration = AppAnimations.scaled(context, AppAnimations.normal);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1,
                duration: duration,
                curve: AppAnimations.spring,
                child: Icon(selected ? item.selectedIcon : item.icon, color: color, size: 24),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: duration,
                style: AppTypography.caption.copyWith(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
