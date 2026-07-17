import 'dart:io';

import 'package:endevir_cli/src/enumerate.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('endevir_enumerate');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  void writeFile(String name, String content) =>
      File('${tempDir.path}/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);

  group('enumerateTests', () {
    test('複数ファイルからグループ修飾つきでテスト名を静的抽出する（ADR-005）', () {
      writeFile('login_test.dart', '''
import 'package:endevir/endevir.dart';
void main() {
  endevirGroup('ログイン', () {
    endevirTest('成功する', (e) async {});
  });
  endevirTest('単独', (e) async {});
}
''');
      writeFile('home_test.dart', '''
import 'package:endevir/endevir.dart';
const _feature = 'ホーム';
void main() {
  endevirTest('\$_feature画面が表示される', (e) async {});
}
''');

      final result = enumerateTests(tempDir.path);

      expect(result.entries.map((e) => e.fullName).toList(), [
        'ホーム画面が表示される', // ファイルパス順（home < login）
        'ログイン > 成功する',
        '単独',
      ]);
      expect(result.warnings, isEmpty);
    });

    test('動的なテスト名（ループ・未解決の補間）は警告として報告する', () {
      writeFile('dynamic_test.dart', '''
import 'package:endevir/endevir.dart';
void main() {
  for (final tab in ['a', 'b']) {
    endevirTest('タブ\$tab', (e) async {});
  }
}
''');

      final result = enumerateTests(tempDir.path);

      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('dynamic_test.dart'));
    });

    test('main_test.dartと生成ファイル（*.g.dart）は列挙対象外', () {
      writeFile('main_test.dart', '''
void main() {}
''');
      writeFile('test_bundle.g.dart', '''
void registerAllTests() {}
''');
      writeFile('real_test.dart', '''
import 'package:endevir/endevir.dart';
void main() {
  endevirTest('本物', (e) async {});
}
''');

      final result = enumerateTests(tempDir.path);

      expect(result.entries.map((e) => e.fullName), ['本物']);
      expect(result.files, ['real_test.dart']);
    });
  });

  group('generateBundle', () {
    test('全テストファイルをimportしてregisterAllTestsで登録するコードを生成する', () {
      writeFile('login_test.dart', '''
import 'package:endevir/endevir.dart';
void main() { endevirTest('t1', (e) async {}); }
''');
      writeFile('flows/checkout_test.dart', '''
import 'package:endevir/endevir.dart';
void main() { endevirTest('t2', (e) async {}); }
''');

      final result = enumerateTests(tempDir.path);
      final bundle = generateBundle(result);

      expect(bundle, contains('GENERATED'));
      expect(bundle, contains("import 'flows/checkout_test.dart' as"));
      expect(bundle, contains("import 'login_test.dart' as"));
      expect(bundle, contains('void registerAllTests()'));
      // 各ファイルのmain（登録）が呼ばれる
      expect(RegExp(r'\.main\(\);').allMatches(bundle), hasLength(2));
    });
  });
}
