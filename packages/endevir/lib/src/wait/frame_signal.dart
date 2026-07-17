import 'package:flutter/scheduler.dart';

/// フレーム終端イベントの供給源。
///
/// イベント駆動待機（ADR-001）はフレーム終端でのみ条件を再評価する。
/// 本番は[SchedulerFrameSignal]（SchedulerBinding）を使い、
/// 単体テストでは手動ティッカーを注入して決定的にテストする。
abstract interface class FrameSignal {
  /// 次のフレーム終端で[callback]を1回呼ぶ。フレームを誘発してはならない。
  void onNextFrame(void Function() callback);

  /// フレームを1回要求する。静止した画面でも初回評価を走らせるために使う。
  void requestFrame();
}

/// SchedulerBindingによる本番実装。
class SchedulerFrameSignal implements FrameSignal {
  const SchedulerFrameSignal();

  @override
  void onNextFrame(void Function() callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) => callback());
  }

  @override
  void requestFrame() {
    SchedulerBinding.instance.scheduleFrame();
  }
}
