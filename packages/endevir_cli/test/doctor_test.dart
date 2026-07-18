import 'dart:io';

import 'package:endevir_cli/src/doctor_command.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('endevir_doctor_test');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('doctorChecks（プロジェクト構成）', () {
    test('endevir依存とendevir_testが揃っていればok', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: my_app
dependencies:
  endevir: any
''');
      Directory('${tempDir.path}/endevir_test').createSync();
      File('${tempDir.path}/endevir_test/main_test.dart')
          .writeAsStringSync('void main() {}');

      final results = runProjectChecks(tempDir.path);

      expect(results.every((r) => r.status != DoctorStatus.fail), isTrue,
          reason: results.join('\n'));
    });

    test('endevir依存がなければfailし、修正方法を提示する', () {
      File('${tempDir.path}/pubspec.yaml')
          .writeAsStringSync('name: my_app\n');

      final results = runProjectChecks(tempDir.path);

      final dep = results.firstWhere((r) => r.name.contains('依存'));
      expect(dep.status, DoctorStatus.fail);
      expect(dep.fixHint, contains('endevir init'));
    });

    test('テストエントリポイントがなければfailする', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: my_app
dependencies:
  endevir: any
''');

      final results = runProjectChecks(tempDir.path);

      final entry = results.firstWhere((r) => r.name.contains('エントリポイント'));
      expect(entry.status, DoctorStatus.fail);
    });
  });

  group('JDKチェック（S6の落とし穴、ADR-006）', () {
    test('Java 21以下はok、22以上はwarnになる', () {
      expect(checkJavaVersion('openjdk version "17.0.18"').status,
          DoctorStatus.ok);
      expect(checkJavaVersion('openjdk version "21.0.2"').status,
          DoctorStatus.ok);
      final warned = checkJavaVersion('openjdk version "25.0.2"');
      expect(warned.status, DoctorStatus.warn);
      expect(warned.fixHint, isNotNull);
    });

    test('javaが見つからない場合はwarn（Android開発をしないなら問題ない）', () {
      expect(checkJavaVersion(null).status, DoctorStatus.warn);
    });
  });

  group('doctor summary', () {
    const ok = DoctorResult('ok', DoctorStatus.ok, 'ready');
    const warning = DoctorResult('warning', DoctorStatus.warn, 'check this');
    const error = DoctorResult('error', DoctorStatus.fail, 'broken');

    test('警告なしの場合だけOKと表示する', () {
      final summary = DoctorSummary([ok]);

      expect(summary.status, DoctorOverallStatus.ok);
      expect(summary.format(), contains('status: OK'));
      expect(summary.exitCode(), 0);
    });

    test('warning-onlyはsuccess with warningsとして明示する', () {
      final summary = DoctorSummary([ok, warning]);

      expect(summary.status, DoctorOverallStatus.warnings);
      expect(summary.format(), contains('status: WARNING'));
      expect(summary.format(), contains('warnings: 1'));
      expect(summary.format(), isNot(contains('問題は見つかりません')));
      expect(summary.exitCode(), 0);
      expect(summary.exitCode(strictWarnings: true), 2);
    });

    test('errorは警告の有無によらず終了コード1にする', () {
      final summary = DoctorSummary([ok, warning, error]);

      expect(summary.status, DoctorOverallStatus.errors);
      expect(summary.format(), contains('status: ERROR'));
      expect(summary.format(), contains('errors: 1, warnings: 1'));
      expect(summary.exitCode(), 1);
      expect(summary.exitCode(strictWarnings: true), 1);
    });
  });
}
