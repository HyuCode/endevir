import 'dart:ui';

/// 要素位置の安定判定（actionability checkの一部、ADR-003）。
///
/// 画面遷移アニメーション中の要素は「存在するが操作できない」
/// （exists ≠ actionable）。タップ前に位置が[requiredFrames]連続で
/// 不変であることを確認する。
class StabilityTracker {
  StabilityTracker({this.requiredFrames = 3})
      : assert(requiredFrames > 0, 'requiredFrames must be positive');

  /// 安定と判定するのに必要な連続不変フレーム数。
  final int requiredFrames;

  Offset? _previous;
  int _stableFrames = 0;

  /// フレームごとの位置を与える。安定に達したらtrueを返す。
  ///
  /// [position]がnull（要素未検出）または前回から移動していた場合、
  /// 連続カウントはリセットされる。
  bool update(Offset? position) {
    if (position != null && _previous != null && position == _previous) {
      _stableFrames++;
    } else {
      _stableFrames = 0;
    }
    _previous = position;
    return _stableFrames >= requiredFrames;
  }
}
