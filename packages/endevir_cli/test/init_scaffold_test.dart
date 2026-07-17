import 'dart:io';

import 'package:endevir_cli/src/init_command.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('endevir_init_test');
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: my_app
environment:
  sdk: ^3.11.0
dependencies:
  flutter:
    sdk: flutter
''');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('scaffoldProject', () {
    test('endevir_test/main_test.dart と endevir.yaml を生成する', () {
      final created = scaffoldProject(tempDir.path);

      final mainTest = File('${tempDir.path}/endevir_test/main_test.dart');
      expect(mainTest.existsSync(), isTrue);
      final content = mainTest.readAsStringSync();
      // アプリのパッケージ名がimportに反映される
      expect(content, contains("import 'package:my_app/main.dart'"));
      expect(content, contains('endevirRunnerMain'));
      expect(content, contains('endevirTest'));

      expect(File('${tempDir.path}/endevir.yaml').existsSync(), isTrue);
      expect(created, containsAll(['endevir_test/main_test.dart', 'endevir.yaml']));
    });

    test('冪等: 既存ファイルは上書きしない（CLI-001）', () {
      scaffoldProject(tempDir.path);
      final mainTest = File('${tempDir.path}/endevir_test/main_test.dart');
      mainTest.writeAsStringSync('// ユーザーが編集した内容');

      final created = scaffoldProject(tempDir.path);

      expect(mainTest.readAsStringSync(), '// ユーザーが編集した内容');
      expect(created, isEmpty, reason: '2回目は何も生成しない');
    });

    test('pubspec.yamlがないディレクトリではエラーになる', () {
      final notAProject = Directory.systemTemp.createTempSync('not_project');
      addTearDown(() => notAProject.deleteSync(recursive: true));

      expect(() => scaffoldProject(notAProject.path), throwsStateError);
    });
  });
}
