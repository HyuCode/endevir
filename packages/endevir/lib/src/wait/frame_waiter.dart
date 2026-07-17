import 'dart:async';

import 'frame_signal.dart';
import 'wait_exception.dart';

/// イベント駆動待機のコア（ADR-001）。
///
/// 条件をフレーム終端でのみ再評価する。UIが静止していれば再評価は発生せず、
/// タイマーポーリングを行わない。要素はフレームによってのみ出現しうるため、
/// フレーム終端での再評価に理論上の取りこぼしはない。
class FrameWaiter {
  FrameWaiter(this._signal);

  final FrameSignal _signal;

  /// [condition]が真になるまでフレーム終端で再評価して待つ。
  ///
  /// [timeout]を超えると[WaitTimeoutException]（[describe]と評価回数つき）で
  /// 失敗する。成立時は[WaitResult]（所要時間・評価回数）を返す。
  Future<WaitResult> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    required String describe,
    bool keepFramesFlowing = false,
  }) {
    final stopwatch = Stopwatch()..start();
    var evaluations = 0;

    bool evaluate() {
      evaluations++;
      return condition();
    }

    if (evaluate()) {
      return Future.value(WaitResult(stopwatch.elapsed, evaluations));
    }

    final completer = Completer<WaitResult>();
    final timer = Timer(timeout, () {
      if (completer.isCompleted) return;
      completer.completeError(
        WaitTimeoutException(
          'wait failed: $describe',
          timeout,
          evaluations: evaluations,
        ),
      );
    });

    void scheduleCheck() {
      _signal.onNextFrame(() {
        if (completer.isCompleted) return;
        if (evaluate()) {
          timer.cancel();
          completer.complete(WaitResult(stopwatch.elapsed, evaluations));
        } else {
          scheduleCheck();
          // 連続フレームでの評価が必要な条件（位置安定判定など）は、
          // 静止した画面ではフレームが流れないため自前で次フレームを要求する
          if (keepFramesFlowing) _signal.requestFrame();
        }
      });
    }

    scheduleCheck();
    // 静止した画面でも初回のフレーム終端評価が走るよう、1フレームだけ要求する
    _signal.requestFrame();
    return completer.future;
  }
}
