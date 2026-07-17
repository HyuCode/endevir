// Endevirテストエントリポイント。
// endevir_test/*_test.dart のテストは生成バンドル経由で自動登録される（CORE-104）。
import 'package:endevir/endevir.dart';
import 'package:example_app/main.dart';

import 'test_bundle.g.dart';

Future<void> main() => endevirRunnerMain(
      registerTests: registerAllTests,
      appBuilder: () => const ExampleApp(),
    );
