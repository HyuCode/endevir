// `endevir init`: プロジェクトへのEndevir導入（CLI-001）。
// 雛形生成は冪等（既存ファイルを上書きしない）。
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:args/args.dart';

import 'enumerate.dart';
import 'flutter_cli.dart';

/// 雛形（endevir_test/main_test.dart, endevir.yaml）を生成する。
/// 生成したファイルの相対パス一覧を返す（既存はスキップ）。
List<String> scaffoldProject(String projectRoot) {
  final pubspec = File('$projectRoot/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw StateError(
        'pubspec.yamlが見つかりません。Flutterプロジェクトのルートで実行してください');
  }
  final packageName = RegExp(r'^name:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec.readAsStringSync())
          ?.group(1) ??
      'app';

  final created = <String>[];

  void write(String relativePath, String content) {
    final file = File('$projectRoot/$relativePath');
    if (file.existsSync()) return; // 冪等: 上書きしない
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    created.add(relativePath);
  }

  write('endevir_test/main_test.dart', _mainTestTemplate(packageName));
  write('endevir_test/app_smoke_test.dart', _smokeTestTemplate);
  write('endevir.yaml', _configTemplate);

  // 初期バンドルを生成する（以後は `endevir test` が毎回再生成する）
  writeBundle(enumerateTests('$projectRoot/endevir_test'));
  return created;
}

/// 列挙結果からtest_bundle.g.dartを書き出す（毎回上書き。生成物のため）。
void writeBundle(EnumerationResult enumeration) {
  File('${enumeration.testDir}/test_bundle.g.dart')
      .writeAsStringSync(generateBundle(enumeration));
}

String _mainTestTemplate(String packageName) => '''
import 'package:endevir/endevir.dart';
import 'package:$packageName/main.dart';

import 'test_bundle.g.dart';

Future<void> main() => endevirRunnerMain(
      // endevir_test/*_test.dart のテストは自動で登録されます（生成バンドル経由）
      registerTests: registerAllTests,
      // アプリのルートWidgetに置き換えてください
      appBuilder: () => const MyApp(),
    );
''';

const _smokeTestTemplate = '''
import 'package:endevir/endevir.dart';
import 'package:flutter/material.dart';

void main() {
  endevirTest('アプリが起動する', (e) async {
    // 最初の画面に表示されるテキスト等に置き換えてください
    await e.expectVisible(MaterialApp);
  });
}
''';

const _configTemplate = '''
# Endevir 実行設定。テスト単位のAPI引数はこの既定値を上書きします。
timeoutSeconds: 10 # 待機のデフォルトタイムアウト
stabilityFrames: 3 # タップ前の位置安定判定に必要な連続不変フレーム数
retries: 0 # 失敗テストのリトライ回数
''';

Future<int> runInitCommand(List<String> args) async {
  final parser = ArgParser()
    ..addOption('endevir-path',
        help: 'Endevirモノレポへのパス（pub.dev公開前のpath依存用）')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(args);
  if (options['help'] as bool) {
    print('usage: endevir init [--endevir-path <path>]');
    print(parser.usage);
    return 0;
  }

  final created = scaffoldProject(Directory.current.path);
  for (final path in created) {
    print('[endevir] created: $path');
  }
  if (created.isEmpty) {
    print('[endevir] 雛形は既に存在します（上書きしません）');
  }

  // 依存追加（pub.dev公開前はpath依存）
  final endevirPath = options['endevir-path'] as String?;
  final specs = endevirPath != null
      ? [
          'endevir:{"path":"$endevirPath/packages/endevir"}',
          'dev:endevir_cli:{"path":"$endevirPath/packages/endevir_cli"}',
          // 未公開の推移的依存はoverrideで解決する（pub.dev公開後は不要）
          'override:endevir_reporter:{"path":"$endevirPath/packages/endevir_reporter"}',
        ]
      : ['endevir', 'dev:endevir_cli'];
  print('[endevir] add dependencies: endevir, endevir_cli');
  final result = await Process.run(
    flutterExecutable(),
    [...flutterArgPrefix(), 'pub', 'add', ...specs],
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    return 1;
  }

  print('');
  print('[endevir] 導入完了。次のコマンドでテストを実行できます:');
  print('  dart run endevir_cli:endevir_cli test -p ios -d <device>');
  return 0;
}

