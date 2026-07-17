import 'dart:async';

/// 待機結果。所要時間と再評価回数（イベント駆動の証跡）を持つ。
class WaitResult {
  const WaitResult(this.elapsed, this.evaluations);

  /// 待機開始から条件成立までの時間。
  final Duration elapsed;

  /// 条件が再評価された回数。フレーム数に比例する（ポーリングではない）。
  final int evaluations;

  @override
  String toString() =>
      'WaitResult(elapsed: ${elapsed.inMilliseconds}ms, '
      'evaluations: $evaluations)';
}

/// タイムアウト時にも再評価回数を持ち出せる待機例外。
class WaitTimeoutException extends TimeoutException {
  WaitTimeoutException(
    String super.message,
    Duration super.duration, {
    required this.evaluations,
  });

  /// タイムアウトまでに条件が再評価された回数。
  final int evaluations;
}
