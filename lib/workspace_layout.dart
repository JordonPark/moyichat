import 'dart:ui';

import 'package:flutter/widgets.dart';

class WorkspaceLayout {
  const WorkspaceLayout({
    required this.sidebarWidth,
    required this.sidebarGap,
    required this.showsSideToolbar,
    required this.chatInsets,
    required this.composerHeight,
    required this.foldGap,
    required this.short,
  });

  factory WorkspaceLayout.fit({
    required Size size,
    required EdgeInsets safeArea,
    required List<DisplayFeature> features,
    required bool compactWidth,
    required double toolbarWidth,
    required double keyboardHeight,
  }) {
    final width = (size.width - safeArea.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final height = (size.height - safeArea.vertical).clamp(
      0.0,
      double.infinity,
    );
    final visibleHeight = height - keyboardHeight;
    // A narrow cover display can already lose width to the system status area.
    final showsSideToolbar = toolbarWidth > 0 && width - toolbarWidth >= 360;
    final toolbar = showsSideToolbar ? toolbarWidth : 0.0;
    final window = Offset.zero & Size(width, height);
    Rect? bookFold;
    Rect? tabletopFold;
    for (final feature in features) {
      if (feature.type != DisplayFeatureType.hinge &&
          !(feature.type == DisplayFeatureType.fold &&
              feature.state == DisplayFeatureState.postureHalfOpened)) {
        continue;
      }
      final fold = feature.bounds.shift(Offset(-safeArea.left, -safeArea.top));
      if (fold.height >= height * .7 &&
          fold.height > fold.width &&
          fold.left > 0 &&
          fold.right < window.right) {
        bookFold = fold;
      } else if (fold.width >= width * .7 &&
          fold.width > fold.height &&
          fold.top > 0 &&
          fold.bottom < window.bottom) {
        tabletopFold = fold;
      }
    }

    double sidebar = 0;
    double divider = 0;
    var chatInsets = EdgeInsets.zero;
    if (bookFold != null) {
      final trailingWidth = width - bookFold.right;
      if (bookFold.left >= 190 && trailingWidth >= 260) {
        // Leave breathing room on both sides of a crease with no physical gap.
        sidebar = bookFold.left - 4;
        divider = bookFold.width + 8;
      } else {
        chatInsets = bookFold.left >= trailingWidth
            ? EdgeInsets.only(right: width - bookFold.left)
            : EdgeInsets.only(left: bookFold.right);
      }
    } else if (!compactWidth &&
        width - toolbar >= 600 &&
        tabletopFold == null) {
      sidebar = ((width - toolbar) * .32).clamp(220.0, 286.0);
      divider = 1;
    }

    final composerHeight =
        tabletopFold != null &&
            tabletopFold.top >= 140 &&
            visibleHeight - tabletopFold.bottom >= 130
        ? visibleHeight - tabletopFold.bottom
        : 0.0;
    if (tabletopFold != null &&
        composerHeight == 0 &&
        visibleHeight > tabletopFold.top &&
        tabletopFold.top >= 140) {
      chatInsets = EdgeInsets.only(
        bottom: visibleHeight - tabletopFold.top + 4,
      );
    }
    return WorkspaceLayout(
      sidebarWidth: sidebar,
      sidebarGap: divider,
      showsSideToolbar: showsSideToolbar,
      chatInsets: chatInsets,
      composerHeight: composerHeight,
      foldGap: composerHeight > 0 ? (tabletopFold!.height + 8) : 0,
      short: visibleHeight < 390 || tabletopFold != null,
    );
  }

  final double sidebarWidth;
  final double sidebarGap;
  final bool showsSideToolbar;
  final EdgeInsets chatInsets;
  final double composerHeight;
  final double foldGap;
  final bool short;

  bool get showsSidebar => sidebarWidth > 0;
}
