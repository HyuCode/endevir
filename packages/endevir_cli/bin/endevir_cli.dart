// Endevir CLI エントリポイント。
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:endevir_cli/src/develop_command.dart';
import 'package:endevir_cli/src/doctor_command.dart';
import 'package:endevir_cli/src/init_command.dart';
import 'package:endevir_cli/src/native_command.dart';
import 'package:endevir_cli/src/test_command.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: endevir <command>');
    print('commands:');
    print('  init     プロジェクトへEndevirを導入する');
    print('  doctor   環境・プロジェクトを診断する');
    print('  test     テストを実行してtraceを回収する');
    print('  develop  修正のたびにホットリスタートで再実行する');
    print('  native   ネイティブテスト写像（instrumentation）を生成・実行する');
    exit(64);
  }
  final command = args.first;
  final rest = args.skip(1).toList();
  final exitCode = switch (command) {
    'init' => await runInitCommand(rest),
    'doctor' => await runDoctorCommand(rest),
    'test' => await runTestCommand(rest),
    'develop' => await runDevelopCommand(rest),
    'native' => await runNativeCommand(rest),
    _ => _unknown(command),
  };
  exit(exitCode);
}

int _unknown(String command) {
  stderr.writeln('unknown command: $command');
  return 64;
}
