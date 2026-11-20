import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyichat/workspace_layout.dart';

WorkspaceLayout fit(
  Size size, {
  EdgeInsets safeArea = EdgeInsets.zero,
  List<DisplayFeature> features = const [],
  bool compactWidth = false,
  double toolbarWidth = 0,
  double keyboardHeight = 0,
}) => WorkspaceLayout.fit(
  size: size,
  safeArea: safeArea,
  features: features,
  compactWidth: compactWidth,
  toolbarWidth: toolbarWidth,
  keyboardHeight: keyboardHeight,
);

void main() {
  test('uses one pane on the cover and two on the unfolded screen', () {
    expect(fit(const Size(347, 882)).showsSidebar, isFalse);
    expect(fit(const Size(674, 882)).showsSidebar, isTrue);
  });

  test('honors the iOS compact trait and asymmetric safe area', () {
    const size = Size(735, 450);
    const safeArea = EdgeInsets.only(right: 70, left: 10);
    expect(
      fit(
        size,
        safeArea: safeArea,
        compactWidth: true,
        toolbarWidth: 52,
      ).showsSidebar,
      isFalse,
    );
    expect(fit(size, safeArea: safeArea, toolbarWidth: 52).sidebarWidth, 220);
  });

  test('keeps both panes clear of a vertical hinge', () {
    final layout = fit(
      const Size(700, 820),
      safeArea: const EdgeInsets.only(left: 12),
      features: const [
        DisplayFeature(
          bounds: Rect.fromLTRB(333, 0, 357, 820),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
    );
    expect(layout.sidebarWidth, 317);
    expect(layout.sidebarGap, 32);
  });

  test('puts the composer below a tabletop fold when there is room', () {
    const features = [
      DisplayFeature(
        bounds: Rect.fromLTRB(0, 414, 700, 422),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    const size = Size(700, 820);
    final layout = fit(size, features: features);
    expect(layout.showsSidebar, isFalse);
    expect(layout.composerHeight, 398);
    expect(layout.foldGap, 16);
    final typing = fit(size, features: features, keyboardHeight: 330);
    expect(typing.composerHeight, 0);
    expect(typing.chatInsets.bottom, 80);
  });
}
