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

  group('Flutter JDKチェック（S6の落とし穴、ADR-006）', () {
    String doctorOutput(int major, String binary) => '''
[✓] Android toolchain - develop for Android devices
    • Java binary at: $binary
      This JDK is specified in your Flutter configuration.
    • Java version OpenJDK Runtime Environment (build $major.0.2+1)
''';

    test('flutter doctorから実際のJava binaryとversionを抽出する', () {
      final info = parseFlutterJava(
        doctorOutput(17, '/opt/homebrew/opt/openjdk@17/bin/java'),
      );

      expect(info, isNotNull);
      expect(info!.major, 17);
      expect(info.binary, '/opt/homebrew/opt/openjdk@17/bin/java');
      expect(info.version, contains('17.0.2'));
    });

    test('Java 17〜21はokになる', () {
      expect(checkFlutterJava(doctorOutput(17, '/jdk17/bin/java')).status,
          DoctorStatus.ok);
      expect(checkFlutterJava(doctorOutput(21, '/jdk21/bin/java')).status,
          DoctorStatus.ok);
    });

    test('Java 17未満と22以上はwarnになり設定コマンドを提示する', () {
      for (final major in [11, 22, 26]) {
        final warned =
            checkFlutterJava(doctorOutput(major, '/jdk$major/bin/java'));
        expect(warned.status, DoctorStatus.warn, reason: 'Java $major');
        expect(warned.message, contains('/jdk$major/bin/java'));
        expect(warned.fixHint, contains('flutter config --jdk-dir'));
      }
    });

    test('Flutterが使用するJavaを特定できない場合はwarnになる', () {
      expect(checkFlutterJava(null).status, DoctorStatus.warn);
      expect(checkFlutterJava('[!] Android toolchain unavailable').status,
          DoctorStatus.warn);
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
