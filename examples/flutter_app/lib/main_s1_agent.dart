// M0スパイク S1用エントリポイント: アプリ内エージェントを起動してから通常起動する。
import 'package:flutter/material.dart';

import 'main.dart';
import 's1_agent.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startAgent();
  runApp(const ExampleApp());
}
