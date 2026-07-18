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

  /// [position]を指定時間押し続ける。
  Future<void> longPressAt(
    Offset position, {
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', '0より大きい値が必要です');
    }
    final pointer = ++_nextPointerId;
    final viewId =
        GestureBinding.instance.platformDispatcher.implicitView!.viewId;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        viewId: viewId,
        pointer: pointer,
        position: position,
        buttons: kPrimaryButton,
      ),
    );
    await Future<void>.delayed(duration);
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        viewId: viewId,
        pointer: pointer,
        timeStamp: duration,
        position: position,
      ),
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

  /// [start]から[delta]方向へ[duration]をかけてスワイプする。
  Future<void> swipeBy(
    Offset start,
    Offset delta, {
    Duration duration = const Duration(milliseconds: 250),
    int steps = 12,
  }) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', '0より大きい値が必要です');
    }
    if (steps < 1) throw ArgumentError.value(steps, 'steps', '1以上が必要です');
    return dragBy(
      start,
      delta,
      steps: steps,
      stepDuration: Duration(
        microseconds: (duration.inMicroseconds / steps).round(),
      ),
    );
  }

  /// [start]から[delta]方向へ指定速度でフリングする。
  Future<void> flingBy(
    Offset start,
    Offset delta, {
    double velocity = 1500,
    int steps = 8,
  }) {
    if (delta == Offset.zero) {
      throw ArgumentError.value(delta, 'delta', '0ではない移動量が必要です');
    }
    if (!velocity.isFinite || velocity <= 0) {
      throw ArgumentError.value(velocity, 'velocity', '正の有限値が必要です');
    }
    if (steps < 1) throw ArgumentError.value(steps, 'steps', '1以上が必要です');
    final totalDurationUs = (delta.distance / velocity * 1000000).round();
    return dragBy(
      start,
      delta,
      steps: steps,
      stepDuration: Duration(
        microseconds: (totalDurationUs / steps).round().clamp(1, 1000000),
      ),
    );
  }
}
