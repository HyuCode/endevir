import 'dart:io';

import 'package:endevir_cli/src/build_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('endevir_build_cache');
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: sample\n');
    File('${project.path}/lib/main.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');
    File('${project.path}/endevir_test/main_test.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');
    File('${project.path}/build/app.apk')
      ..createSync(recursive: true)
      ..writeAsStringSync('apk');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('unchanged project artifact is reusable', () {
    writeBuildManifest(
      projectRoot: project.path,
      outDir: '${project.path}/.endevir',
      platform: 'android',
      target: 'endevir_test/main_test.dart',
      artifactPath: 'build/app.apk',
      now: DateTime.utc(2026, 7, 20),
    );

    final result = validateReusableBuild(
      projectRoot: project.path,
      outDir: '${project.path}/.endevir',
      platform: 'android',
      target: 'endevir_test/main_test.dart',
    );

    expect(result.isValid, isTrue);
    expect(result.manifest?.builtAt, DateTime.utc(2026, 7, 20));
  });

  test('iOS app directory is accepted as an artifact', () {
    Directory('${project.path}/build/Runner.app').createSync(recursive: true);
    writeBuildManifest(
      projectRoot: project.path,
      outDir: '${project.path}/.endevir',
      platform: 'ios',
      target: 'endevir_test/main_test.dart',
      artifactPath: 'build/Runner.app',
    );

    final result = validateReusableBuild(
      projectRoot: project.path,
      outDir: '${project.path}/.endevir',
      platform: 'ios',
      target: 'endevir_test/main_test.dart',
    );

    expect(result.isValid, isTrue);
  });

  test('source changes invalidate the artifact', () {
    writeBuildManifest(
      projectRoot: project.path,
      outDir: '${project.path}/.endevir',
      platform: 'android',
      target: 'endevir_test/main_test.dart',
      artifactPath: 'build/app.apk',
    );
    File(
      '${project.path}/lib/main.dart',
    ).writeAsStringSync('void changed() {}');

    final result = validateReusableBuild(
      projectRoot: project.path,
      outDir: '${project.path}/.endevir',
      platform: 'android',
      target: 'endevir_test/main_test.dart',
    );

    expect(result.isValid, isFalse);
    expect(result.message, contains('inputs changed'));
  });

  test('test target changes invalidate the artifact', () {
    writeBuildManifest(
      projectRoot: project.path,
      outDir: '${project.path}/.endevir',
      platform: 'android',
      target: 'endevir_test/main_test.dart',
      artifactPath: 'build/app.apk',
    );

    final result = validateReusableBuild(
      projectRoot: project.path,
      outDir: '${project.path}/.endevir',
      platform: 'android',
      target: 'endevir_test/other.dart',
    );

    expect(result.isValid, isFalse);
    expect(result.message, contains('target changed'));
  });

  test('generated build output does not change the fingerprint', () {
    final before = computeProjectFingerprint(project.path);
    File('${project.path}/build/generated.txt').writeAsStringSync('changed');
    Directory('${project.path}/android/.gradle').createSync(recursive: true);
    File('${project.path}/android/.gradle/cache').writeAsStringSync('changed');

    expect(computeProjectFingerprint(project.path), before);
  });
}
