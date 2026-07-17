import 'package:endevir_reporter/endevir_reporter.dart';

import '../tester/endevir_tester.dart';
import 'test_registry.dart';

/// 実行結果の集計。
class RunSummary {
  const RunSummary({required this.total, required this.passed, required this.failed});

  final int total;
  final int passed;
  final int failed;
}

/// 登録済みテストを実行し、traceへ記録するランナー。
///
/// テスト単位のライフサイクル（testStart/testEnd）と失敗の隔離
/// （1件の失敗が後続を止めない）を担う。
class EndevirTestRunner {
  EndevirTestRunner({
    required TraceWriter writer,
    required EndevirTester Function(int testId) testerFactory,
  })  : _writer = writer,
        _testerFactory = testerFactory;

  final TraceWriter _writer;
  final EndevirTester Function(int testId) _testerFactory;

  /// [registry]の全テスト（[only]指定時は名前一致のみ）を実行する。
  Future<RunSummary> run(
    EndevirTestRegistry registry, {
    required String runId,
    required String platform,
    String? only,
  }) async {
    _writer.runStart(runId: runId, platform: platform);
    var passed = 0;
    var failed = 0;

    final targets = registry.entries
        .where((entry) => only == null || entry.name == only)
        .toList();

    for (final entry in targets) {
      final testId = _writer.testStart(entry.name);
      try {
        await entry.body(_testerFactory(testId));
        _writer.testEnd(testId, TraceStatus.PASSED);
        passed++;
      } catch (e) {
        _writer.testEnd(testId, TraceStatus.FAILED, error: '$e');
        failed++;
      }
    }

    _writer.runEnd();
    return RunSummary(total: targets.length, passed: passed, failed: failed);
  }
}
