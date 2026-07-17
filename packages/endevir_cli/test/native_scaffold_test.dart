import 'dart:convert';
import 'dart:io';

import 'package:endevir_cli/src/native_command.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('endevir_native');
    File('${tempDir.path}/android/app/build.gradle.kts')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
android {
    namespace = "com.example.my_app"

    defaultConfig {
        applicationId = "com.example.my_app"
        minSdk = flutter.minSdkVersion
    }
}

flutter {
    source = "../.."
}
''');
    File('${tempDir.path}/endevir_test/login_test.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:endevir/endevir.dart';
void main() {
  endevirTest('ログインできる', (e) async {});
}
''');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('scaffoldAndroidNative', () {
    test('Kotlinランナー・マニフェスト・assetsマニフェストを生成する', () {
      scaffoldAndroidNative(tempDir.path);

      final kotlin = File('${tempDir.path}/android/app/src/androidTest/'
          'kotlin/com/example/my_app/EndevirNativeTest.kt');
      expect(kotlin.existsSync(), isTrue);
      final kotlinContent = kotlin.readAsStringSync();
      expect(kotlinContent, contains('package com.example.my_app'));
      expect(kotlinContent, contains('Parameterized'));
      expect(kotlinContent, contains('/runTest'));
      expect(kotlinContent, contains('GENERATED'));

      final manifest = File('${tempDir.path}/android/app/src/androidTest/'
          'AndroidManifest.xml');
      expect(manifest.readAsStringSync(), contains('android:exported'));

      final assets = File('${tempDir.path}/android/app/src/androidTest/'
          'assets/endevir_manifest.json');
      final entries = jsonDecode(assets.readAsStringSync()) as List;
      expect(entries.map((e) => (e as Map)['fullName']), ['ログインできる']);
    });

    test('build.gradle.ktsにrunnerとandroidTest依存を冪等に注入する', () {
      scaffoldAndroidNative(tempDir.path);
      scaffoldAndroidNative(tempDir.path); // 2回実行しても重複しない

      final gradle = File('${tempDir.path}/android/app/build.gradle.kts')
          .readAsStringSync();
      expect(
        RegExp('testInstrumentationRunner').allMatches(gradle),
        hasLength(1),
      );
      expect(
        RegExp('androidx\\.test:runner:1\\.2\\.0').allMatches(gradle),
        hasLength(1),
      );
      // ADR-006: Flutter embeddingの制約に合わせたバージョン
      expect(gradle, contains('androidx.test.ext:junit:1.1.1'));
    });

    test('applicationIdが見つからない場合はエラーになる', () {
      File('${tempDir.path}/android/app/build.gradle.kts')
          .writeAsStringSync('android {}');

      expect(() => scaffoldAndroidNative(tempDir.path), throwsStateError);
    });
  });
}
