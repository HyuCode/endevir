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

  group('buildDependencyPlan', () {
    test('既定はpub.devの通常依存とdev依存を追加する', () {
      final plan = buildDependencyPlan();

      expect(plan.source, EndevirDependencySource.hosted);
      expect(plan.specs, ['endevir', 'dev:endevir_cli']);
      expect(plan.description, 'pub.dev');
    });

    test('pathはmonorepo内3パッケージを同じ絶対pathへ揃える', () {
      final plan = buildDependencyPlan(path: tempDir.path);

      expect(plan.source, EndevirDependencySource.path);
      expect(plan.specs, [
        'endevir:{"path":"${tempDir.path}/packages/endevir"}',
        'dev:endevir_cli:{"path":"${tempDir.path}/packages/endevir_cli"}',
        'override:endevir_reporter:{"path":"${tempDir.path}/packages/endevir_reporter"}',
      ]);
    });

    test('gitはurl/ref/subdirectoryを3パッケージへ揃える', () {
      final plan = buildDependencyPlan(
        git: 'https://github.com/HyuCode/endevir.git',
        ref: 'abc123',
      );

      expect(plan.source, EndevirDependencySource.git);
      for (final spec in plan.specs) {
        expect(spec, contains('"url":"https://github.com/HyuCode/endevir.git"'));
        expect(spec, contains('"ref":"abc123"'));
      }
      expect(plan.specs[0], contains('"path":"packages/endevir"'));
      expect(plan.specs[1], contains('"path":"packages/endevir_cli"'));
      expect(plan.specs[2], contains('"path":"packages/endevir_reporter"'));
    });

    test('git refは省略できる', () {
      final plan = buildDependencyPlan(git: 'git@example.com:repo.git');

      expect(plan.specs.every((spec) => !spec.contains('"ref"')), isTrue);
    });

    test('pathとgitの同時指定、gitなしrefを拒否する', () {
      expect(
        () => buildDependencyPlan(path: '.', git: 'repo.git'),
        throwsArgumentError,
      );
      expect(
        () => buildDependencyPlan(ref: 'main'),
        throwsArgumentError,
      );
    });
  });

  group('scaffoldProject', () {
    test('バンドル方式の雛形一式（bootstrap+サンプル+バンドル+設定）を生成する', () {
      final created = scaffoldProject(tempDir.path);

      final mainTest = File('${tempDir.path}/endevir_test/main_test.dart');
      expect(mainTest.existsSync(), isTrue);
      final content = mainTest.readAsStringSync();
      // アプリのパッケージ名がimportに反映される
      expect(content, contains("import 'package:my_app/main.dart'"));
      expect(content, contains('endevirRunnerMain'));
      // 登録は生成バンドル経由（CORE-104）
      expect(content, contains('registerAllTests'));

      final sample =
          File('${tempDir.path}/endevir_test/app_smoke_test.dart');
      expect(sample.existsSync(), isTrue);
      expect(sample.readAsStringSync(), contains('endevirTest'));

      // 初期バンドルも生成され、サンプルテストが登録される
      final bundle =
          File('${tempDir.path}/endevir_test/test_bundle.g.dart');
      expect(bundle.existsSync(), isTrue);
      expect(bundle.readAsStringSync(), contains('app_smoke_test'));

      expect(File('${tempDir.path}/endevir.yaml').existsSync(), isTrue);
      expect(
        created,
        containsAll([
          'endevir_test/main_test.dart',
          'endevir_test/app_smoke_test.dart',
          'endevir.yaml',
        ]),
      );
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

  group('initializeProject transaction', () {
    Future<ProcessResult> failingPubAdd(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async {
      final root = workingDirectory!;
      File('$root/pubspec.yaml').writeAsStringSync('''
name: my_app
dependencies:
  endevir:
    path: /temporary/endevir/packages/endevir
''');
      File('$root/pubspec.lock').writeAsStringSync('partial lock');
      File('$root/.dart_tool/package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('partial config');
      return ProcessResult(1, 1, '', 'version solving failed');
    }

    test('pub add失敗時にpubspecと新規雛形・生成ディレクトリを戻す', () async {
      final originalPubspec =
          File('${tempDir.path}/pubspec.yaml').readAsStringSync();

      final result = await initializeProject(
        projectRoot: tempDir.path,
        dependencySpecs: const ['endevir'],
        flutter: 'flutter',
        processRunner: failingPubAdd,
      );

      expect(result.exitCode, 1);
      expect(result.rolledBack, isTrue);
      expect(result.error, contains('version solving failed'));
      expect(File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
          originalPubspec);
      expect(File('${tempDir.path}/pubspec.lock').existsSync(), isFalse);
      expect(Directory('${tempDir.path}/endevir_test').existsSync(), isFalse);
      expect(Directory('${tempDir.path}/.dart_tool').existsSync(), isFalse);
      expect(File('${tempDir.path}/endevir.yaml').existsSync(), isFalse);
    });

    test('既存ファイルとbundleを失敗後にbyte単位で復元する', () async {
      final testDir = Directory('${tempDir.path}/endevir_test')..createSync();
      final mainTest = File('${testDir.path}/main_test.dart')
        ..writeAsStringSync('// user main');
      final bundle = File('${testDir.path}/test_bundle.g.dart')
        ..writeAsStringSync('// previous bundle');
      final lock = File('${tempDir.path}/pubspec.lock')
        ..writeAsStringSync('previous lock');

      final result = await initializeProject(
        projectRoot: tempDir.path,
        dependencySpecs: const ['endevir'],
        flutter: 'flutter',
        processRunner: failingPubAdd,
      );

      expect(result.rolledBack, isTrue);
      expect(mainTest.readAsStringSync(), '// user main');
      expect(bundle.readAsStringSync(), '// previous bundle');
      expect(lock.readAsStringSync(), 'previous lock');
      expect(File('${testDir.path}/app_smoke_test.dart').existsSync(), isFalse);
      expect(testDir.existsSync(), isTrue);
    });

    test('成功時は雛形とpub addの変更を確定する', () async {
      final result = await initializeProject(
        projectRoot: tempDir.path,
        dependencySpecs: const ['endevir'],
        flutter: 'flutter',
        processRunner: (
          executable,
          arguments, {
          workingDirectory,
        }) async {
          expect(workingDirectory, tempDir.path);
          expect(arguments, ['pub', 'add', 'endevir']);
          File('${workingDirectory!}/pubspec.yaml')
              .writeAsStringSync('name: my_app\ndependencies:\n  endevir: any\n');
          return ProcessResult(1, 0, '', '');
        },
      );

      expect(result.exitCode, 0);
      expect(result.rolledBack, isFalse);
      expect(File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
          contains('endevir: any'));
      expect(Directory('${tempDir.path}/endevir_test').existsSync(), isTrue);
    });

    test('pub processを開始できない場合もrollbackする', () async {
      final result = await initializeProject(
        projectRoot: tempDir.path,
        dependencySpecs: const ['endevir'],
        flutter: 'missing-flutter',
        processRunner: (
          executable,
          arguments, {
          workingDirectory,
        }) async =>
            throw ProcessException(executable, arguments, 'not found'),
      );

      expect(result.exitCode, 1);
      expect(result.rolledBack, isTrue);
      expect(Directory('${tempDir.path}/endevir_test').existsSync(), isFalse);
    });
  });
}
