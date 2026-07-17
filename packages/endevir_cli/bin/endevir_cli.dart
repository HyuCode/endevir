// Endevir CLI エントリポイント。
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:endevir_cli/src/test_command.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: endevir <command>');
    print('commands:');
    print('  test    テストを実行してtraceを回収する');
    exit(64);
  }
  final command = args.first;
  final rest = args.skip(1).toList();
  final exitCode = switch (command) {
    'test' => await runTestCommand(rest),
    _ => _unknown(command),
  };
  exit(exitCode);
}

int _unknown(String command) {
  stderr.writeln('unknown command: $command');
  return 64;
}
