import 'package:flutter/widgets.dart';

/// Navigatorをルートまで戻す（テスト間の簡易状態リセット）。
///
/// より強い分離（アプリ再起動・状態クリア）はネイティブ写像側の
/// テストごと再起動（ADR-006）で行う。
void popToRoot({Element? root}) {
  final rootElement = root ?? WidgetsBinding.instance.rootElement;
  NavigatorState? navigator;
  void visit(Element element) {
    if (navigator != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      navigator = element.state as NavigatorState;
      return;
    }
    element.visitChildren(visit);
  }

  rootElement?.visitChildren(visit);
  navigator?.popUntil((route) => route.isFirst);
}
