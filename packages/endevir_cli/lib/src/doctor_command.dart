// `endevir doctor`: 環境・プロジェクト診断（CLI-002）。
// M0/S6で実証した落とし穴（ADR-006）を診断項目として持つ。
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:args/args.dart';

import 'flutter_cli.dart';

enum DoctorStatus { ok, warn, fail }

enum DoctorOverallStatus { ok, warnings, errors }

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

class FlutterJavaInfo {
  const FlutterJavaInfo({
    required this.binary,
    required this.version,
    required this.major,
  });

  final String binary;
  final String version;
  final int major;
}

class DoctorSummary {
  DoctorSummary(Iterable<DoctorResult> results)
      : okCount = results.where((r) => r.status == DoctorStatus.ok).length,
        warningCount =
            results.where((r) => r.status == DoctorStatus.warn).length,
        errorCount =
            results.where((r) => r.status == DoctorStatus.fail).length;

  final int okCount;
  final int warningCount;
  final int errorCount;

  DoctorOverallStatus get status => errorCount > 0
      ? DoctorOverallStatus.errors
      : warningCount > 0
          ? DoctorOverallStatus.warnings
          : DoctorOverallStatus.ok;

  /// Errors always fail with 1. Warnings are a successful diagnosis by
  /// default, or exit 2 when a CI caller opts into strict warning handling.
  int exitCode({bool strictWarnings = false}) => switch (status) {
        DoctorOverallStatus.ok => 0,
        DoctorOverallStatus.warnings => strictWarnings ? 2 : 0,
        DoctorOverallStatus.errors => 1,
      };

  String format() => switch (status) {
        DoctorOverallStatus.ok =>
          '[endevir] doctor status: OK ($okCount checks passed)',
        DoctorOverallStatus.warnings =>
          '[endevir] doctor status: WARNING '
              '(warnings: $warningCount, errors: $errorCount; success with warnings)',
        DoctorOverallStatus.errors =>
          '[endevir] doctor status: ERROR '
              '(errors: $errorCount, warnings: $warningCount)',
      };
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

/// Extracts the Java selected by Flutter for Android/Gradle. This deliberately
/// does not inspect shell `java`, which may differ from Flutter configuration.
FlutterJavaInfo? parseFlutterJava(String flutterDoctorOutput) {
  final binary = RegExp(r'Java binary at:\s*(.+)')
      .firstMatch(flutterDoctorOutput)
      ?.group(1)
      ?.trim();
  final version = RegExp(r'Java version\s+(.+)')
      .firstMatch(flutterDoctorOutput)
      ?.group(1)
      ?.trim();
  final major = version == null
      ? null
      : int.tryParse(
          RegExp(r'\(build\s+(\d+)').firstMatch(version)?.group(1) ?? '');
  if (binary == null || binary.isEmpty || version == null || major == null) {
    return null;
  }
  return FlutterJavaInfo(binary: binary, version: version, major: major);
}

/// JDK compatibility check based on `flutter doctor -v`, which reports the
/// Java binary Flutter actually passes to Android tooling.
DoctorResult checkFlutterJava(String? flutterDoctorOutput) {
  final info = flutterDoctorOutput == null
      ? null
      : parseFlutterJava(flutterDoctorOutput);
  if (info == null) {
    return const DoctorResult(
      'Flutter JDK',
      DoctorStatus.warn,
      'Flutterが使用するJavaを特定できません',
      fixHint: '`flutter doctor -v` のAndroid toolchainを確認してください',
    );
  }
  if (info.major < 17 || info.major > 21) {
    return DoctorResult(
      'Flutter JDK',
      DoctorStatus.warn,
      'Java ${info.major} はAndroid Gradle/Kotlinビルドと非互換の可能性があります '
          '(${info.binary})',
      fixHint: '`flutter config --jdk-dir=<JDK 17〜21のパス>` を実行してください',
    );
  }
  return DoctorResult(
    'Flutter JDK',
    DoctorStatus.ok,
    'Java ${info.major} (${info.binary})',
  );
}

Future<int> runDoctorCommand(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('strict',
        negatable: false, help: '警告が1件以上ある場合に終了コード2を返します')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(args);
  if (options['help'] as bool) {
    print('usage: endevir doctor [--strict]');
    print(parser.usage);
    return 0;
  }

  final results = <DoctorResult>[...runProjectChecks(Directory.current.path)];

  // ツールチェーン検査
  results.add(await _checkCommand(
      'Flutter SDK', flutterExecutable(), [...flutterArgPrefix(), '--version']));
  results.add(checkFlutterJava(await _flutterDoctorOutput()));
  if (Platform.isMacOS) {
    results.add(await _checkCommand('Xcodeツール', 'xcrun', ['--version']));
  }
  results.add(await _checkCommand('adb', 'adb', ['--version'],
      warnOnly: true, fixHint: 'Androidでテストする場合はAndroid SDKが必要です'));

  for (final result in results) {
    print(result);
  }

  final summary = DoctorSummary(results);
  print('');
  print(summary.format());
  return summary.exitCode(strictWarnings: options['strict'] as bool);
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

Future<String?> _flutterDoctorOutput() async {
  try {
    final result = await Process.run(
      flutterExecutable(),
      [...flutterArgPrefix(), 'doctor', '-v'],
    );
    return '${result.stdout}${result.stderr}';
  } on ProcessException {
    return null;
  }
}
