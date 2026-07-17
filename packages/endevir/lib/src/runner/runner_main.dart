import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../agent/endevir_agent.dart';
import '../evidence/evidence_recorder.dart';
import '../interaction/navigation.dart';
import '../tester/endevir_tester.dart';
import 'test_registry.dart';
import 'test_runner.dart';

/// Endevirテスト実行用エントリポイント。
///
/// テストエントリポイント（endevir_test/main_test.dart等）から呼ぶ:
/// ```dart
/// Future<void> main() => endevirRunnerMain(
///       registerTests: () {
///         endevirTest('...', (e) async { ... });
///       },
///       appBuilder: () => const MyApp(),
///     );
/// ```
///
/// アプリを起動し、エージェント（ADR-002）でホストからの実行要求を待つ。
/// traceはWebSocket経由でストリームされる。
Future<void> endevirRunnerMain({
  required void Function() registerTests,
  required Widget Function() appBuilder,
  int port = 8808,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  endevirRegistry.clear();
  registerTests();

  final agent = EndevirAgent(
    listTests: () =>
        endevirRegistry.entries.map((entry) => entry.name).toList(),
    runTests: ({only, config, required onTraceLine, required onScreenshot}) async {
      final effective = config ?? const EndevirRunConfig();
      final writer = TraceWriter(onTraceLine);
      final recorder = EvidenceRecorder(
        capturer: const DebugLayerFrameCapturer(),
        deliver: onScreenshot,
      );
      final runner = EndevirTestRunner(
        writer: writer,
        testerFactory: (testId, attempt) => EndevirTester(
          writer: writer,
          testId: testId,
          attempt: attempt,
          defaultTimeout: effective.timeout,
          stabilityFrames: effective.stabilityFrames,
          evidence: recorder,
          screenshotMode: effective.screenshotMode,
        ),
        // テスト間の簡易状態リセット（強い分離はネイティブ写像側で行う）
        beforeEach: () async => popToRoot(),
      );
      final summary = await runner.run(
        endevirRegistry,
        runId: 'run-${DateTime.now().microsecondsSinceEpoch}',
        platform: defaultTargetPlatform.name,
        only: only,
        retries: effective.retries,
      );
      // 遅延エンコードの完了（=全スクリーンショットの配送）を待ってから応答する
      await recorder.flush();
      return summary;
    },
  );
  await agent.start(port: port);
  runApp(appBuilder());
}
