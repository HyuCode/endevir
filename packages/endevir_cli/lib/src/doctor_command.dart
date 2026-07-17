// `endevir doctor`: 環境・プロジェクト診断（CLI-002）。
// M0/S6で実証した落とし穴（ADR-006）を診断項目として持つ。
// ignore_for_file: avoid_print
import 'dart:io';

import 'flutter_cli.dart';

enum DoctorStatus { ok, warn, fail }

class DoctorResult {
  const DoctorResult(this.name, this.status, this.message, {this.fixHint});

  final String name;
  final DoctorStatus status;
  final String message;
  final String? fixHint;

  @override
  String toString() {
    final icon = switch (status) {
      DoctorStatus.ok => '✓',
      DoctorStatus.warn => '!',
      DoctorStatus.fail => '✗',
    };
    final hint = fixHint != null ? '\n    → $fixHint' : '';
    return '[$icon] $name: $message$hint';
  }
}

/// プロジェクト構成のチェック（純粋なファイル検査、テスト可能）。
List<DoctorResult> runProjectChecks(String projectRoot) {
  final results = <DoctorResult>[];

  final pubspec = File('$projectRoot/pubspec.yaml');
  if (!pubspec.existsSync()) {
    return [
      const DoctorResult('プロジェクト', DoctorStatus.fail,
          'pubspec.yamlが見つかりません',
          fixHint: 'Flutterプロジェクトのルートで実行してください'),
    ];
  }

  final pubspecContent = pubspec.readAsStringSync();
  results.add(pubspecContent.contains(RegExp(r'^\s{2}endevir:', multiLine: true))
      ? const DoctorResult('endevir依存', DoctorStatus.ok, 'pubspec.yamlに定義済み')
      : const DoctorResult('endevir依存', DoctorStatus.fail,
          'pubspec.yamlにendevirがありません',
          fixHint: '`endevir init` を実行してください'));

  final entry = File('$projectRoot/endevir_test/main_test.dart');
  results.add(entry.existsSync()
      ? const DoctorResult(
          'テストエントリポイント', DoctorStatus.ok, 'endevir_test/main_test.dart')
      : const DoctorResult('テストエントリポイント', DoctorStatus.fail,
          'endevir_test/main_test.dartがありません',
          fixHint: '`endevir init` を実行してください'));

  final config = File('$projectRoot/endevir.yaml');
  results.add(config.existsSync()
      ? const DoctorResult('実行設定', DoctorStatus.ok, 'endevir.yaml')
      : const DoctorResult(
          '実行設定', DoctorStatus.warn, 'endevir.yamlなし（既定値で動作します)'));

  return results;
}

/// JDKバージョンのチェック（ADR-006の落とし穴1: 新しすぎるJDKでgradleが落ちる）。
/// [javaVersionOutput]は `java -version` の出力（javaがなければnull）。
DoctorResult checkJavaVersion(String? javaVersionOutput) {
  if (javaVersionOutput == null) {
    return const DoctorResult('JDK', DoctorStatus.warn, 'javaが見つかりません',
        fixHint: 'Androidでテストする場合はJDK 17〜21を用意してください');
  }
  final match =
      RegExp(r'version "(\d+)').firstMatch(javaVersionOutput);
  final major = int.tryParse(match?.group(1) ?? '');
  if (major == null) {
    return DoctorResult(
        'JDK', DoctorStatus.warn, '不明なjavaバージョン: $javaVersionOutput');
  }
  if (major > 21) {
    return DoctorResult('JDK', DoctorStatus.warn,
        'Java $major はAndroid Gradle/Kotlinビルドと非互換の可能性があります',
        fixHint: 'JDK 17〜21を使用してください（例: JAVA_HOME=/opt/homebrew/opt/openjdk@17）');
  }
  return DoctorResult('JDK', DoctorStatus.ok, 'Java $major');
}

Future<int> runDoctorCommand(List<String> args) async {
  final results = <DoctorResult>[...runProjectChecks(Directory.current.path)];

  // ツールチェーン検査
  results.add(await _checkCommand(
      'Flutter SDK', flutterExecutable(), [...flutterArgPrefix(), '--version']));
  results.add(checkJavaVersion(await _javaVersion()));
  if (Platform.isMacOS) {
    results.add(await _checkCommand('Xcodeツール', 'xcrun', ['--version']));
  }
  results.add(await _checkCommand('adb', 'adb', ['--version'],
      warnOnly: true, fixHint: 'Androidでテストする場合はAndroid SDKが必要です'));

  for (final result in results) {
    print(result);
  }

  final failed =
      results.where((r) => r.status == DoctorStatus.fail).length;
  print('');
  print(failed == 0
      ? '[endevir] 問題は見つかりませんでした'
      : '[endevir] $failed 件の問題があります');
  return failed == 0 ? 0 : 1;
}

Future<DoctorResult> _checkCommand(
  String name,
  String executable,
  List<String> args, {
  bool warnOnly = false,
  String? fixHint,
}) async {
  try {
    final result = await Process.run(executable, args);
    if (result.exitCode == 0) {
      final firstLine =
          '${result.stdout}${result.stderr}'.trim().split('\n').first;
      return DoctorResult(name, DoctorStatus.ok, firstLine);
    }
    return DoctorResult(name,
        warnOnly ? DoctorStatus.warn : DoctorStatus.fail, '実行に失敗しました',
        fixHint: fixHint);
  } on ProcessException {
    return DoctorResult(name,
        warnOnly ? DoctorStatus.warn : DoctorStatus.fail, '見つかりません',
        fixHint: fixHint);
  }
}

Future<String?> _javaVersion() async {
  try {
    final result = await Process.run('java', ['-version']);
    // java -versionはstderrに出力される
    return '${result.stderr}${result.stdout}';
  } on ProcessException {
    return null;
  }
}

