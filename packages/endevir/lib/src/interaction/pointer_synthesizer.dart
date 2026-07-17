
import 'package:flutter/gestures.dart';

/// 論理座標でポインタイベントを合成するタップの原型（S1/S6で実証済み）。
///
/// WidgetTester/テストバインディングに依存せず、本番モードで動作する。
class PointerSynthesizer {
  int _nextPointerId = 0;

  /// [position]（論理座標）をタップする。
  Future<void> tapAt(Offset position) async {
    final pointer = ++_nextPointerId;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: pointer, position: position),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: pointer, position: position),
    );
  }
}
