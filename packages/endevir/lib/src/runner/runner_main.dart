import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../agent/endevir_agent.dart';
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
    runTests: ({only, required onTraceLine}) {
      final writer = TraceWriter(onTraceLine);
      final runner = EndevirTestRunner(
        writer: writer,
        testerFactory: (testId) =>
            EndevirTester(writer: writer, testId: testId),
        // テスト間の簡易状態リセット（強い分離はネイティブ写像側で行う）
        beforeEach: () async => popToRoot(),
      );
      return runner.run(
        endevirRegistry,
        runId: 'run-${DateTime.now().microsecondsSinceEpoch}',
        platform: defaultTargetPlatform.name,
        only: only,
      );
    },
  );
  await agent.start(port: port);
  runApp(appBuilder());
}
