// M0スパイク S5: ホットリスタートによるテスト再実行（CLI-102の原型）。
//
// 起動時（=ホットリスタート時）に毎回ミニテストシナリオを自動実行し、
// 結果をログに出す。ホスト側はflutter attachでアタッチし、
// 「コード修正 → R（ホットリスタート）→ シナリオ再実行」のループ秒数を計測する。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'main.dart';
import 's1_agent.dart';

/// コード変更がデバイスに届いたことを証明するバージョン印。
/// ホスト側がこの値を書き換えてホットリスタートし、ログで確認する。
const scenarioVersion = 'v1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
  unawaited(_runScenario());
}

Future<void> _runScenario() async {
  final stopwatch = Stopwatch()..start();
  try {
    await _waitForText('Endevir Example');
    await _waitForStablePosition('nav_infinite_animation');
    await tapByKey('nav_infinite_animation');
    await _waitForText('カウント: 0');
    // 【S5の発見】テキストは遷移アニメーションの初フレームで既に存在するため、
    // 存在確認だけで即タップすると遷移中の要素を空振りする（exists≠actionable）。
    // タップ前に要素位置が連続フレームで安定するのを待つ（actionability check）。
    await _waitForStablePosition('increment_button');
    await tapByKey('increment_button');
    await _waitForText('カウント: 1');
    debugPrint(
      'S5-TEST PASSED ($scenarioVersion) in ${stopwatch.elapsedMilliseconds}ms',
    );
  } catch (e) {
    debugPrint('S5-TEST FAILED ($scenarioVersion): $e');
  }
}

/// 要素の位置が3連続フレームで不変になるまで待つ（actionability checkの原型）。
/// 全体静止待ち（quiescence）と違い、無限アニメーション画面でも成立する。
Future<void> _waitForStablePosition(
  String keyValue, {
  Duration timeout = const Duration(seconds: 10),
}) {
  final completer = Completer<void>();
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException('position not stable: $keyValue'),
      );
    }
  });

  Offset? previous;
  var stableFrames = 0;

  void scheduleCheck() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (completer.isCompleted) return;
      final current = globalCenterOf(keyValue);
      if (current != null && previous != null && current == previous) {
        stableFrames++;
      } else {
        stableFrames = 0;
      }
      previous = current;
      if (stableFrames >= 3) {
        timer.cancel();
        completer.complete();
      } else {
        scheduleCheck();
        SchedulerBinding.instance.scheduleFrame();
      }
    });
  }

  scheduleCheck();
  SchedulerBinding.instance.scheduleFrame();
  return completer.future;
}

/// フレーム終端でテキストの出現を待つ（S3のイベント駆動待機の本番モード版）。
Future<void> _waitForText(
  String value, {
  Duration timeout = const Duration(seconds: 10),
}) {
  if (textExists(value)) return Future<void>.value();

  final completer = Completer<void>();
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException('text not found: $value'));
    }
  });

  void scheduleCheck() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (completer.isCompleted) return;
      if (textExists(value)) {
        timer.cancel();
        completer.complete();
      } else {
        scheduleCheck();
      }
    });
    // 静止中でも初回チェックが走るよう1フレームだけ要求する
    SchedulerBinding.instance.scheduleFrame();
  }

  scheduleCheck();
  return completer.future;
}
