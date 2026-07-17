// M0スパイク S6用エントリポイント: エージェント起動 + テストバンドル登録 + 通常起動。
// ネイティブ側（instrumentation）が /runTest?name=... で1テストずつ実行する。
import 'package:example_app/main.dart';
import 'package:example_app/s1_agent.dart';
import 'package:flutter/material.dart';

import 'test_bundle.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerTestEntries(testEntries);
  await startAgent();
  runApp(const ExampleApp());
}
