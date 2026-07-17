// M0スパイク S2/S6用のEndevir APIスタブ。
// 「endevirTestは登録、実行はランナー」の構造（ADR-005）と、
// 本番モードで実UIを操作するテスターAPIの最小形を提供する。
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 's1_agent.dart';

typedef EndevirTestCallback = Future<void> Function(EndevirTester e);

/// 実行対象のテスト名（ネイティブ写像時に1テストだけ実行するためのフィルタ）。
String? endevirTargetTest;

Future<void>? _pendingExecution;

/// テストを宣言する。対象フィルタに一致した場合のみ実行をスケジュールする。
void endevirTest(String description, EndevirTestCallback body) {
  if (endevirTargetTest != null && endevirTargetTest != description) return;
  _pendingExecution = body(const EndevirTester());
}

/// テストのグループ化（flutter_testのgroupと同形）。
void endevirGroup(String description, void Function() body) {
  body();
}

/// バンドルのエントリ実行: 対象を1件に絞ってファイルmain（登録）を呼び、
/// スケジュールされた実行の完了を待つ。
Future<void> runBundleEntry(String target, void Function() registrar) async {
  popToRoot(); // テスト間の簡易状態リセット
  endevirTargetTest = target;
  _pendingExecution = null;
  try {
    registrar();
    final pending = _pendingExecution;
    if (pending == null) {
      throw StateError('test not found in file: $target');
    }
    await pending;
  } finally {
    endevirTargetTest = null;
    _pendingExecution = null;
  }
}

/// 本番モード（テストバインディング不要）で実UIを操作するテスター。
/// S1エージェントのポインタ合成とS3のイベント駆動待機を組み合わせた最小API。
class EndevirTester {
  const EndevirTester();

  /// 位置安定（actionability check、ADR-003）を待ってからタップする。
  Future<void> tap(String keyValue) async {
    await _waitForStablePosition(keyValue);
    final result = await tapByKey(keyValue);
    if (result['ok'] != true) {
      throw StateError('tap failed: $result');
    }
  }

  /// テキストの出現をフレーム終端で待つ（ADR-001）。
  Future<void> expectText(
    String value, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (textExists(value)) return Future<void>.value();
    return _waitOnFrames(
      () => textExists(value),
      timeout: timeout,
      describe: 'text: $value',
    );
  }

  Future<void> _waitForStablePosition(
    String keyValue, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    Offset? previous;
    var stableFrames = 0;
    return _waitOnFrames(
      () {
        final current = globalCenterOf(keyValue);
        if (current != null && previous != null && current == previous) {
          stableFrames++;
        } else {
          stableFrames = 0;
        }
        previous = current;
        return stableFrames >= 3;
      },
      timeout: timeout,
      describe: 'stable: $keyValue',
    );
  }
}

Future<void> _waitOnFrames(
  bool Function() condition, {
  required Duration timeout,
  required String describe,
}) {
  final completer = Completer<void>();
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException('wait failed: $describe'));
    }
  });

  void scheduleCheck() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (completer.isCompleted) return;
      if (condition()) {
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
