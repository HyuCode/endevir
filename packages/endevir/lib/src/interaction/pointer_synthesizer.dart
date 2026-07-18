import 'dart:async';

import 'package:flutter/gestures.dart';

/// 論理座標でポインタイベントを合成するタップの原型（S1/S6で実証済み）。
///
/// WidgetTester/テストバインディングに依存せず、本番モードで動作する。
class PointerSynthesizer {
  int _nextPointerId = 0;

  /// [position]（論理座標）をタップする。
  Future<void> tapAt(Offset position) async {
    final pointer = ++_nextPointerId;
    final viewId =
        GestureBinding.instance.platformDispatcher.implicitView!.viewId;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(viewId: viewId, pointer: pointer, position: position),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(viewId: viewId, pointer: pointer, position: position),
    );
  }

  /// [start]から[delta]分だけドラッグする。
  ///
  /// 複数のmoveイベントをフレーム間隔で送ることで、Dismissibleなどの
  /// ジェスチャー認識を本番モードでも成立させる。
  Future<void> dragBy(
    Offset start,
    Offset delta, {
    int steps = 12,
    Duration stepDuration = const Duration(milliseconds: 16),
  }) async {
    if (steps < 1) throw ArgumentError.value(steps, 'steps', '1以上が必要です');

    final pointer = ++_nextPointerId;
    final viewId =
        GestureBinding.instance.platformDispatcher.implicitView!.viewId;
    var previous = start;
    var elapsed = Duration.zero;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        viewId: viewId,
        pointer: pointer,
        position: start,
        buttons: kPrimaryButton,
      ),
    );

    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(stepDuration);
      elapsed += stepDuration;
      final position = start + delta * (i / steps);
      GestureBinding.instance.handlePointerEvent(
        PointerMoveEvent(
          viewId: viewId,
          pointer: pointer,
          timeStamp: elapsed,
          position: position,
          delta: position - previous,
          buttons: kPrimaryButton,
        ),
      );
      previous = position;
    }

    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        viewId: viewId,
        pointer: pointer,
        timeStamp: elapsed,
        position: previous,
      ),
    );
  }
}
