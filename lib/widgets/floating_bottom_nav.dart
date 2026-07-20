import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/nutripulse_theme_controller.dart';

class FloatingBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isCompact;

  const FloatingBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isCompact = false,
  });

  static const List<IconData> icons = [
    Icons.grid_view_rounded,
    Icons.restaurant_rounded,
    Icons.monitor_heart_rounded,
    Icons.directions_run_rounded,
    Icons.groups_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: nutriThemeController,
      builder: (context, _) {
        final p = nutriThemeController.palette;
        final screenWidth = MediaQuery.of(context).size.width;

        final baseWidth = screenWidth < 380
            ? screenWidth * 0.95
            : screenWidth < 430
            ? screenWidth * 0.90
            : 388.0;

        final navWidth = isCompact ? baseWidth * 0.86 : baseWidth;
        final navHeight = isCompact ? 58.0 : 72.0;
        final horizontalPadding = isCompact ? 8.0 : 10.0;
        final bubbleSize = isCompact ? 44.0 : 56.0;
        final selectedIconSize = isCompact ? 22.0 : 25.0;
        final normalIconSize = isCompact ? 20.5 : 23.0;

        return Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: navWidth,
            height: navHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth =
                    (constraints.maxWidth - (horizontalPadding * 2)) /
                    icons.length;
                final bubbleLeft =
                    horizontalPadding +
                    (itemWidth * currentIndex) +
                    ((itemWidth - bubbleSize) / 2);

                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: isCompact ? 16 : 12,
                          sigmaY: isCompact ? 16 : 12,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            color: p.navBg.withOpacity(isCompact ? 0.72 : 0.84),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(
                                isCompact ? 0.06 : 0.08,
                              ),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  isCompact ? 0.22 : 0.30,
                                ),
                                blurRadius: isCompact ? 18 : 24,
                                offset: Offset(0, isCompact ? 9 : 14),
                              ),
                              BoxShadow(
                                color: Colors.white.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      left: bubbleLeft,
                      top: (navHeight - bubbleSize) / 2,
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          width: bubbleSize,
                          height: bubbleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                p.lime.withOpacity(isCompact ? 0.82 : 0.92),
                                p.lime,
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(
                                isCompact ? 0.12 : 0.18,
                              ),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: p.lime.withOpacity(
                                  isCompact ? 0.12 : 0.22,
                                ),
                                blurRadius: isCompact ? 10 : 18,
                                offset: Offset(0, isCompact ? 5 : 8),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Row(
                        children: List.generate(icons.length, (index) {
                          final selected = currentIndex == index;

                          return SizedBox(
                            width: itemWidth,
                            height: navHeight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onTap(index),
                              child: Center(
                                child: AnimatedScale(
                                  scale: selected
                                      ? (isCompact ? 1.02 : 1.04)
                                      : 1.0,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  child: Icon(
                                    icons[index],
                                    size: selected
                                        ? selectedIconSize
                                        : normalIconSize,
                                    color: selected
                                        ? p.selectedIcon
                                        : p.navIcon.withOpacity(
                                            isCompact ? 0.72 : 0.82,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
