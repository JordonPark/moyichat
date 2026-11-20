import 'dart:ui';

import 'package:flutter/widgets.dart';

class WorkspaceLayout {
  const WorkspaceLayout({
    required this.sidebarWidth,
    required this.sidebarGap,
    required this.sideToolbarFrame,
    required this.sideToolbarInsets,
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
    required double keyboardHeight,
    AxisDirection? toolbarEdge,
    Rect? systemToolbarFrame,
  }) {
    final safeBounds = safeArea.deflateRect(Offset.zero & size);
    final toolbar = _placeSideToolbar(
      edge: toolbarEdge,
      systemFrame: systemToolbarFrame,
      size: size,
      safeBounds: safeBounds,
      bottom: size.height - keyboardHeight,
    );
    final toolbarInsets = switch ((toolbarEdge, toolbar)) {
      (AxisDirection.left, final frame?) => EdgeInsets.only(
        left: (frame.right - safeBounds.left).clamp(0.0, safeBounds.width),
      ),
      (AxisDirection.right, final frame?) => EdgeInsets.only(
        right: (safeBounds.right - frame.left).clamp(0.0, safeBounds.width),
      ),
      _ => EdgeInsets.zero,
    };
    final width = (safeBounds.width - toolbarInsets.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final height = (size.height - safeArea.vertical).clamp(
      0.0,
      double.infinity,
    );
    final visibleHeight = height - keyboardHeight;
    final window = Offset.zero & Size(width, height);
    Rect? bookFold;
    Rect? tabletopFold;
    for (final feature in features) {
      if (feature.type != DisplayFeatureType.hinge &&
          !(feature.type == DisplayFeatureType.fold &&
              feature.state == DisplayFeatureState.postureHalfOpened)) {
        continue;
      }
      final fold = feature.bounds.shift(
        Offset(-safeArea.left - toolbarInsets.left, -safeArea.top),
      );
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
    } else if (!compactWidth && width >= 600 && tabletopFold == null) {
      sidebar = (width * .32).clamp(220.0, 286.0);
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
      sideToolbarFrame: toolbar,
      sideToolbarInsets: toolbarInsets,
      chatInsets: chatInsets,
      composerHeight: composerHeight,
      foldGap: composerHeight > 0 ? (tabletopFold!.height + 8) : 0,
      short: visibleHeight < 390 || tabletopFold != null,
    );
  }

  final double sidebarWidth;
  final double sidebarGap;
  final Rect? sideToolbarFrame;
  final EdgeInsets sideToolbarInsets;
  final EdgeInsets chatInsets;
  final double composerHeight;
  final double foldGap;
  final bool short;

  bool get showsSidebar => sidebarWidth > 0;

  static Rect? _placeSideToolbar({
    required AxisDirection? edge,
    required Rect? systemFrame,
    required Size size,
    required Rect safeBounds,
    required double bottom,
  }) {
    if (edge == null || safeBounds.isEmpty) return null;
    const toolbarWidth = 52.0;
    final visible = Rect.fromLTRB(0, 0, size.width, bottom);
    if (systemFrame != null && systemFrame.isFinite) {
      final frame = systemFrame.intersect(visible);
      final onEdge = edge == AxisDirection.left
          ? frame.left <= safeBounds.left + toolbarWidth
          : frame.right >= safeBounds.right - toolbarWidth;
      if (onEdge && !frame.isEmpty) return frame;
    }
    // Keep the controls on the requested side until UIKit publishes its guide.
    final width = safeBounds.width.clamp(0.0, toolbarWidth);
    final left = edge == AxisDirection.left
        ? safeBounds.left
        : safeBounds.right - width;
    final fallback = Rect.fromLTRB(
      left,
      safeBounds.top,
      left + width,
      safeBounds.bottom,
    ).intersect(visible);
    return fallback.isEmpty ? null : fallback;
  }
}
