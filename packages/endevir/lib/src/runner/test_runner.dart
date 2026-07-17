import 'dart:async';

import 'package:endevir_reporter/endevir_reporter.dart';

import '../tester/endevir_tester.dart';
import 'log_correlator.dart';
import 'test_registry.dart';

/// 実行結果の集計。
class RunSummary {
  const RunSummary({
    required this.total,
    required this.passed,
    required this.failed,
    this.flaky = 0,
  });

  final int total;
  final int passed;
  final int failed;

  /// リトライの末に成功したテスト数（passedに含まれる。flake分析の入力）。
  final int flaky;
}

/// 登録済みテストを実行し、traceへ記録するランナー。
///
/// テスト単位のライフサイクル（testStart/testEnd）と失敗の隔離
/// （1件の失敗が後続を止めない）を担う。
class EndevirTestRunner {
  EndevirTestRunner({
    required TraceWriter writer,
    required EndevirTester Function(int testId, int attempt) testerFactory,
    Future<void> Function()? beforeEach,
    LogCorrelator? logCorrelator,
  })  : _writer = writer,
        _testerFactory = testerFactory,
        _beforeEach = beforeEach,
        _logCorrelator = logCorrelator;

  final TraceWriter _writer;
  final EndevirTester Function(int testId, int attempt) _testerFactory;

  /// 各テストの直前に呼ばれるフック（画面状態のリセット等）。
  final Future<void> Function()? _beforeEach;

  /// print/debugPrintのステップ相関（RPT-002/405）。
  final LogCorrelator? _logCorrelator;

  /// [registry]の全テスト（[only]指定時は名前一致のみ）を実行する。
  ///
  /// [retries]は失敗時の再試行回数（CORE-106）。テスト側の個別指定
  /// （`endevirTest(..., retries: n)`）があればそちらが優先される。
  Future<RunSummary> run(
    EndevirTestRegistry registry, {
    required String runId,
    required String platform,
    String? only,
    int retries = 0,
  }) async {
    _writer.runStart(runId: runId, platform: platform);
    var passed = 0;
    var failed = 0;
    var flaky = 0;

    final targets = registry.entries
        .where((entry) => only == null || entry.name == only)
        .toList();

    _logCorrelator?.attach(_writer);
    try {
      for (final entry in targets) {
        final maxAttempts = (entry.retries ?? retries) + 1;
        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          await _beforeEach?.call();
          final testId = _writer.testStart(entry.name, attempt: attempt);
          try {
            await _runBody(entry, testId, attempt);
            _writer.testEnd(testId, TraceStatus.PASSED, attempt: attempt);
            passed++;
            if (attempt > 1) flaky++;
            break;
          } catch (e) {
            _writer.testEnd(testId, TraceStatus.FAILED,
                error: '$e', attempt: attempt);
            if (attempt == maxAttempts) failed++;
          }
        }
      }
    } finally {
      _logCorrelator?.detach();
    }

    _writer.runEnd();
    return RunSummary(
      total: targets.length,
      passed: passed,
      failed: failed,
      flaky: flaky,
    );
  }

  /// テスト本文を実行する。ログ相関が有効な場合、print/debugPrint
  /// （printに合流する）を捕捉ゾーンで包み、現在のステップに相関させる。
  /// コンソールへの出力は維持する（parent.printへ委譲）。
  Future<void> _runBody(EndevirTestEntry entry, int testId, int attempt) {
    final tester = _testerFactory(testId, attempt);
    final correlator = _logCorrelator;
    if (correlator == null) return entry.body(tester);

    return runZoned(
      () => entry.body(tester),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, message) {
          correlator.emit(message);
          parent.print(zone, message);
        },
      ),
    );
  }
}
