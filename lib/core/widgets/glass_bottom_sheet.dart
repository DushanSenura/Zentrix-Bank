import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// Modal sheet with rounded top corners, blurred glass body, drag handle and a spring entrance.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  isDismissible: dismissible,
  enableDrag: dismissible,
  sheetAnimationStyle: AnimationStyle(
    duration: AppAnimations.scaled(context, AppAnimations.slow),
    reverseDuration: AppAnimations.scaled(context, AppAnimations.normal),
    curve: AppAnimations.standard,
  ),
  builder: (context) {
    final c = context.colors;
    const top = Radius.circular(AppRadius.xl);
    // heightFactor keeps the sheet as tall as its content, so taps above it reach the barrier and dismiss it.
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: top),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: c.surface.withAlpha(224),
                border: Border(top: BorderSide(color: c.glassBorder)),
              ),
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(4)),
                    ),
                    // Gives ListTiles and ink effects a surface to paint on.
                    Flexible(child: Material(type: MaterialType.transparency, child: builder(context))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
);
