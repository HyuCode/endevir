// M0スパイク S3: イベント駆動待機（CORE-102）の検証
//
// 問い: フレームスケジューラのシグナル（postFrameCallback / hasScheduledFrame /
// transientCallbackCount）だけで、タイマーポーリングも固定sleepも使わずに
// 「要素の出現」「アニメーション終了」を正しく・低オーバーヘッドで待てるか。
//
// 結果はADR-001に記録する。計測値はdebugPrint（"S3-METRIC"プレフィックス）で出力。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:example_app/main.dart';

/// イベント駆動待機のプロトタイプ（Endevir CORE-102の原型）。
///
/// 設計原則:
/// - 要素はフレームによってのみ出現しうるため、フレーム終端（postFrameCallback）
///   でのみファインダーを再評価する。UIが静止している間は一切CPUを使わない
/// - Maestroの画像差分ポーリング（200ms間隔）やwidget testのpump(100ms)ループと
///   異なり、待機中の再評価回数はフレーム数に比例する（=イベント駆動）
class EventDrivenWaiter {
  EventDrivenWaiter(this.binding);

  final WidgetsBinding binding;

  /// ファインダーがマッチするまでフレーム終端でのみ再評価して待つ。
  Future<WaitResult> waitForMatch(
    Finder finder, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final stopwatch = Stopwatch()..start();
    var evaluations = 0;

    bool isMatched() {
      evaluations++;
      return finder.evaluate().isNotEmpty;
    }

    return _waitUntil(
      isMatched,
      timeout: timeout,
      describe: () => 'waitForMatch($finder)',
      evaluationCount: () => evaluations,
    ).then((_) => WaitResult(stopwatch.elapsed, evaluations));
  }

  /// アニメーションとスケジュール済みフレームがなくなる（UIが静止する）まで待つ。
  Future<WaitResult> waitForQuiescence({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final stopwatch = Stopwatch()..start();
    var evaluations = 0;

    bool isQuiescent() {
      evaluations++;
      final scheduler = SchedulerBinding.instance;
      return scheduler.transientCallbackCount == 0 &&
          !scheduler.hasScheduledFrame;
    }

    return _waitUntil(
      isQuiescent,
      timeout: timeout,
      describe: () => 'waitForQuiescence',
    ).then((_) => WaitResult(stopwatch.elapsed, evaluations));
  }

  Future<void> _waitUntil(
    bool Function() condition, {
    required Duration timeout,
    required String Function() describe,
    int Function()? evaluationCount,
  }) {
    if (condition()) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    late final Timer timeoutTimer;

    void scheduleCheck() {
      binding.addPostFrameCallback((_) {
        if (completer.isCompleted) return;
        if (condition()) {
          timeoutTimer.cancel();
          completer.complete();
        } else {
          scheduleCheck();
        }
      });
    }

    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          WaitTimeoutException(
            '${describe()} timed out',
            timeout,
            evaluations: evaluationCount?.call() ?? -1,
          ),
        );
      }
    });

    scheduleCheck();
    return completer.future;
  }
}

/// タイムアウト時にも再評価回数（アイドルコストの証跡）を持ち出せる例外。
class WaitTimeoutException extends TimeoutException {
  WaitTimeoutException(super.message, super.duration, {required this.evaluations});

  final int evaluations;
}

class WaitResult {
  const WaitResult(this.elapsed, this.evaluations);

  /// 待機開始から条件成立までの実時間。
  final Duration elapsed;

  /// 条件が再評価された回数（フレーム終端でのみ増える）。
  /// ポーリング型との比較指標: 10ms間隔ポーリングなら3秒待機で約300回になる。
  final int evaluations;

  @override
  String toString() =>
      'elapsed=${elapsed.inMilliseconds}ms evaluations=$evaluations';
}

void metric(String name, WaitResult result) {
  // ADR転記用の計測ログ
  debugPrint('S3-METRIC $name: $result');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 【スパイク発見事項】デフォルトのframePolicy（fadePointers）では、アプリの
  // setStateによるフレーム要求がpump()まで描画されず、イベント駆動待機が成立しない。
  // 本番同様にフレームが流れるfullyLiveがEndevirランナーの前提条件になる（ADR-001）。
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('S3-1 遅延ロード: 3秒後の要素出現をsleepなしで検知できる', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    final waiter = EventDrivenWaiter(binding);

    await tester.tap(find.byKey(const Key('nav_delayed_load')));
    await tester.pump();

    final result = await waiter.waitForMatch(
      find.byKey(const Key('loaded_content')),
    );
    metric('delayed_load', result);

    // 3秒の遅延に対して検知オーバーヘッドが1秒未満であること
    expect(result.elapsed.inMilliseconds, inInclusiveRange(2900, 4000));
    // 再評価はフレーム数に比例する（イベント駆動の性質）。
    // この画面はローディングスピナーが60fpsでフレームを流すため約180回になる。
    // 比較: Maestroは200ms間隔のスクリーンショット撮影+画像差分（1回あたりの
    // コストが桁違いに大きい）。ファインダー評価はウィジェットツリー走査のみ。
    expect(result.evaluations, lessThan(250));
  });

  testWidgets('S3-5 待機器はフレームを追加しない（再評価は1フレーム1回）', (tester) async {
    // 【スパイク発見事項】LiveTestWidgetsFlutterBinding.handleDrawFrame は
    // benchmark以外の全ポリシーで毎フレーム後に platformDispatcher.scheduleFrame()
    // を無条件に呼ぶため、integration_test環境では静止画面でも常時60fpsになる
    // （flutter_test/lib/src/binding.dart 2522-2524行、Flutter 3.41.1）。
    // よって「アイドル時の再評価ゼロ」はこのバインディング上では実現できない。
    // 真のアイドルゼロにはEndevir自前バインディング（M1）が必要（ADR-001）。
    //
    // ここで検証できる（そして重要な）性質は「待機器がフレームを追加せず、
    // 再評価回数がフレーム数に一致する（=イベント駆動）」こと。
    await tester.pumpWidget(const ExampleApp());
    final waiter = EventDrivenWaiter(binding);

    // ベースライン: 待機器なしで2秒間のフレーム数（addTimingsCallbackは
    // フレームを誘発しない）
    var baselineFrames = 0;
    void countBaseline(List<FrameTiming> t) => baselineFrames += t.length;
    binding.addTimingsCallback(countBaseline);
    await Future<void>.delayed(const Duration(seconds: 2));
    binding.removeTimingsCallback(countBaseline);

    // 計測: 待機器を動かした2秒間のフレーム数と再評価回数
    var framesDuringWait = 0;
    void countDuringWait(List<FrameTiming> t) => framesDuringWait += t.length;
    binding.addTimingsCallback(countDuringWait);
    late final WaitTimeoutException timeout;
    try {
      await waiter.waitForMatch(
        find.byKey(const Key('does_not_exist')),
        timeout: const Duration(seconds: 2),
      );
      fail('タイムアウトするはず');
    } on WaitTimeoutException catch (e) {
      timeout = e;
    }
    binding.removeTimingsCallback(countDuringWait);

    debugPrint(
      'S3-METRIC frame_neutrality: baseline=$baselineFrames '
      'duringWait=$framesDuringWait evaluations=${timeout.evaluations}',
    );

    // 待機器がフレームレートを増やしていないこと（±50%の揺らぎ許容）
    expect(framesDuringWait, lessThan(baselineFrames * 1.5));
    // 再評価はフレームごとに高々1回であること（=タイマーポーリングではない）。
    // FrameTimingの通知は非同期バッチのため計測窓から数フレーム漏れうる。
    // 10msポーリングなら約200回になるところ、フレーム数±10に収まることを確認する
    expect(timeout.evaluations, lessThanOrEqualTo(framesDuringWait + 10));
  });

  testWidgets('S3-2 有限アニメーション: 終了（静止）をイベントで検知できる', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    final waiter = EventDrivenWaiter(binding);

    await tester.tap(find.byKey(const Key('nav_animation')));
    await tester.pump();
    await waiter.waitForQuiescence();

    await tester.tap(find.byKey(const Key('toggle_button')));
    await tester.pump();

    final result = await waiter.waitForQuiescence();
    metric('animation_end', result);

    await waiter.waitForMatch(find.text('アニメーション完了: 1回'));

    // 800msのアニメーションに対して過大な待ちが発生しないこと
    expect(result.elapsed.inMilliseconds, inInclusiveRange(700, 3000));
  });

  testWidgets('S3-3 無限アニメーション: 静止は永遠に来ないが、要素待機は成立する', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    final waiter = EventDrivenWaiter(binding);

    await tester.tap(find.byKey(const Key('nav_infinite_animation')));
    await tester.pump();
    await waiter.waitForMatch(find.byKey(const Key('increment_button')));

    // 全体静止待ち（pumpAndSettle相当）は無限アニメーション下ではタイムアウトする
    await expectLater(
      waiter.waitForQuiescence(timeout: const Duration(seconds: 3)),
      throwsA(isA<TimeoutException>()),
    );

    // 一方、要素待機はアニメーション継続中でも成立する（ここが設計の核心）
    await tester.tap(find.byKey(const Key('increment_button')));
    await tester.pump();

    final result = await waiter.waitForMatch(find.text('カウント: 1'));
    metric('infinite_animation_counter', result);

    expect(result.elapsed.inMilliseconds, lessThan(2000));
  });

  testWidgets('S3-4 フォーム: 入力→送信→擬似遅延つき結果表示を待てる', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    final waiter = EventDrivenWaiter(binding);

    await tester.tap(find.byKey(const Key('nav_form')));
    await tester.pump();
    await waiter.waitForMatch(find.byKey(const Key('email_field')));

    await tester.enterText(
      find.byKey(const Key('email_field')),
      'user@example.com',
    );
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pump();

    final result = await waiter.waitForMatch(
      find.byKey(const Key('submit_result')),
    );
    metric('form_submit', result);

    // 1秒の擬似遅延に対して検知オーバーヘッドが1秒未満であること
    expect(result.elapsed.inMilliseconds, inInclusiveRange(900, 2000));
  });
}
