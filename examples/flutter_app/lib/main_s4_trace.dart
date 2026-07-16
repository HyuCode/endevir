// M0スパイク S4: trace記録オーバーヘッドの計測（RPT-001/002/004）。
//
// 同一シナリオを3モードで反復実行し、記録コストを実測する:
//   mode A: 記録なし（ベースライン）
//   mode B: trace（ステップ+タイムスタンプ+JSONL書き込み、スクショなし）
//   mode C: 証跡モード（ステップごとに全画面スクリーンショット）
//
// 結果はS4-METRICプレフィックスでログ出力し、ADRに転記する。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'main.dart';
import 's1_agent.dart';

const _iterations = 10;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
  unawaited(_runBenchmark());
}

Future<void> _runBenchmark() async {
  try {
    await _waitForText('Endevir Example');

    final baseline = await _runMode('A_no_trace', screenshots: false, record: false);
    final trace = await _runMode('B_trace', screenshots: false, record: true);
    final evidence = await _runMode('C_evidence', screenshots: true, record: true);
    final deferred = await _runMode('D_evidence_deferred',
        screenshots: true, record: true, deferEncoding: true);

    String overhead(int mode) =>
        '${((mode - baseline) * 100 / baseline).toStringAsFixed(1)}%';
    debugPrint('S4-METRIC overhead_trace: ${overhead(trace)}');
    debugPrint('S4-METRIC overhead_evidence: ${overhead(evidence)}');
    debugPrint('S4-METRIC overhead_evidence_deferred: ${overhead(deferred)}');
    debugPrint('S4-DONE');
  } catch (e, st) {
    debugPrint('S4-FAILED: $e\n$st');
  }
}

/// 1モード分: シナリオ（4ステップ）をN回反復し、合計時間を計測する。
Future<int> _runMode(
  String mode, {
  required bool screenshots,
  required bool record,
  bool deferEncoding = false,
}) async {
  final recorder = record
      ? TraceRecorder(
          mode: mode,
          screenshots: screenshots,
          deferEncoding: deferEncoding,
        )
      : null;
  final stopwatch = Stopwatch()..start();

  for (var i = 0; i < _iterations; i++) {
    Future<void> step(String name, Future<void> Function() body) =>
        recorder != null ? recorder.step(name, body) : body();

    await step('無限アニメーション画面へ遷移', () async {
      await _waitForStablePosition('nav_infinite_animation');
      await tapByKey('nav_infinite_animation');
      await _waitForText('カウント: 0');
    });
    await step('カウントアップ', () async {
      await _waitForStablePosition('increment_button');
      await tapByKey('increment_button');
    });
    await step('カウント表示を検証', () async {
      await _waitForText('カウント: 1');
    });
    await step('ホームへ戻る', () async {
      _popTopRoute();
      await _waitForText('Endevir Example');
      await _waitForStablePosition('nav_infinite_animation');
    });
  }

  final elapsed = stopwatch.elapsedMilliseconds;
  await recorder?.close();
  debugPrint(
    'S4-METRIC mode_$mode: total=${elapsed}ms '
    'perIteration=${(elapsed / _iterations).toStringAsFixed(0)}ms '
    '${recorder?.summary() ?? ''}',
  );
  return elapsed;
}

/// traceレコーダのプロトタイプ: ステップをJSONLに記録し、
/// 証跡モードではステップ完了ごとに全画面スクリーンショットを撮る。
class TraceRecorder {
  TraceRecorder({
    required this.mode,
    required this.screenshots,
    this.deferEncoding = false,
  }) : _file = File(
          '${Directory.systemTemp.path}/endevir_trace_$mode.jsonl',
        ).openWrite();

  final String mode;
  final bool screenshots;

  /// trueの場合、ステップをブロックするのはGPUスナップショット（toImage）のみで、
  /// PNGエンコードとファイル書き込みは後段に遅延する（正しいフレーム内容は
  /// toImage時点で確定しているため、遅延しても内容は正しい）。
  final bool deferEncoding;
  final IOSink _file;
  final List<Future<void>> _pendingEncodes = [];

  int _stepId = 0;
  int _screenshotCount = 0;
  int _screenshotBytes = 0;
  int _screenshotMs = 0;
  int _toImageMs = 0;
  int _encodeMs = 0;
  int _writeMs = 0;

  Future<void> step(String name, Future<void> Function() body) async {
    final id = ++_stepId;
    final startedAt = DateTime.now().microsecondsSinceEpoch;
    final stopwatch = Stopwatch()..start();
    Object? error;
    try {
      await body();
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      final durationUs = stopwatch.elapsedMicroseconds;
      String? screenshotPath;
      if (screenshots) {
        screenshotPath = await _captureScreenshot(id);
      }
      _file.writeln(jsonEncode({
        'stepId': id,
        'name': name,
        'startedAtUs': startedAt,
        'durationUs': durationUs,
        'status': error == null ? 'passed' : 'failed',
        if (error != null) 'error': '$error',
        'screenshot': ?screenshotPath,
      }));
    }
  }

  Future<String?> _captureScreenshot(int stepId) async {
    final stopwatch = Stopwatch()..start();
    try {
      // debugLayer経由（debugビルド限定）。本番のスクショ取得はプラットフォーム
      // 別機構（エンジンAPI）の設計が必要——ADRの未解決事項に記載
      final renderView = WidgetsBinding.instance.renderViews.first;
      final layer = renderView.debugLayer;
      if (layer is! OffsetLayer) return null;

      // (1) GPUスナップショット: この時点でフレーム内容が確定する
      final image = await layer.toImage(renderView.paintBounds);
      _toImageMs += stopwatch.elapsedMilliseconds;

      final path =
          '${Directory.systemTemp.path}/endevir_shot_${mode}_$stepId.png';

      Future<void> encodeAndWrite() async {
        final encodeSw = Stopwatch()..start();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        _encodeMs += encodeSw.elapsedMilliseconds;
        image.dispose();
        if (byteData == null) return;
        final bytes = byteData.buffer.asUint8List();
        final writeSw = Stopwatch()..start();
        await File(path).writeAsBytes(bytes);
        _writeMs += writeSw.elapsedMilliseconds;
        _screenshotBytes += bytes.length;
      }

      // (2) PNGエンコード + (3) 書き込み: 遅延モードではステップをブロックしない
      if (deferEncoding) {
        _pendingEncodes.add(encodeAndWrite());
      } else {
        await encodeAndWrite();
      }

      _screenshotCount++;
      _screenshotMs += stopwatch.elapsedMilliseconds;
      return path;
    } catch (e) {
      debugPrint('S4-SCREENSHOT-ERROR: $e');
      return null;
    }
  }

  String summary() {
    if (_screenshotCount == 0) return 'steps=$_stepId';
    return 'steps=$_stepId screenshots=$_screenshotCount '
        'avgShotMs=${(_screenshotMs / _screenshotCount).toStringAsFixed(0)} '
        'avgShotKB=${(_screenshotBytes / _screenshotCount / 1024).toStringAsFixed(0)} '
        'avgToImageMs=${(_toImageMs / _screenshotCount).toStringAsFixed(0)} '
        'avgEncodeMs=${(_encodeMs / _screenshotCount).toStringAsFixed(0)} '
        'avgWriteMs=${(_writeMs / _screenshotCount).toStringAsFixed(0)}';
  }

  Future<void> close() async {
    await Future.wait(_pendingEncodes);
    await _file.flush();
    await _file.close();
  }
}

/// Navigatorの最上位ルートをpopする（戻るボタン相当）。
void _popTopRoute() {
  NavigatorState? navigator;
  void visit(Element element) {
    if (navigator != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      navigator = element.state as NavigatorState;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  navigator?.pop();
}

// --- S5から流用したイベント駆動待機ヘルパー（スパイクのため重複を許容） ---

Future<void> _waitForText(
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
