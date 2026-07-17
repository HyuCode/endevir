// M0スパイク S2: ビルド時テスト列挙（CORE-110）の検証。
//
// package:analyzerの構文解析（意味解析なし=高速）でendevirTest/endevirGroupを
// 静的に抽出し、(a) マニフェストJSON、(b) テストバンドル(test_bundle.g.dart)を
// 生成する。Patrolの「全テスト空実行によるドライラン」を置き換えられるかを検証する。
//
// 使い方:
//   fvm dart run tool/s2_enumerate.dart [testDir] [--bundle]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

void main(List<String> args) {
  final dirPath = args.isNotEmpty && !args[0].startsWith('--')
      ? args[0]
      : 'endevir_test';
  final emitBundle = args.contains('--bundle');

  final dir = Directory(dirPath);
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('_test.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final stopwatch = Stopwatch()..start();
  final entries = <TestEntry>[];
  for (final file in files) {
    entries.addAll(_enumerateFile(file));
  }
  final elapsedMs = stopwatch.elapsedMilliseconds;

  final staticCount = entries.where((e) => !e.isDynamic).length;
  final dynamicCount = entries.length - staticCount;
  print('S2-METRIC enumerate: files=${files.length} '
      'tests=${entries.length} static=$staticCount dynamic=$dynamicCount '
      'elapsedMs=$elapsedMs');
  print(const JsonEncoder.withIndent('  ')
      .convert(entries.map((e) => e.toJson()).toList()));

  for (final e in entries.where((e) => e.isDynamic)) {
    print('S2-WARNING 静的に解決できないテスト名: ${e.file}:${e.line} (${e.reason})');
  }

  if (emitBundle) {
    final bundle = _generateBundle(dirPath, files, entries);
    File('$dirPath/test_bundle.g.dart').writeAsStringSync(bundle);
    print('S2-BUNDLE generated: $dirPath/test_bundle.g.dart');
  }

  final manifestOutIndex = args.indexOf('--manifest-out');
  if (manifestOutIndex >= 0 && manifestOutIndex + 1 < args.length) {
    final outPath = args[manifestOutIndex + 1];
    final manifest = entries
        .where((e) => !e.isDynamic)
        .map((e) => {'fullName': e.fullName, 'file': e.file})
        .toList();
    File(outPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(manifest));
    print('S2-MANIFEST generated: $outPath');
  }
}

class TestEntry {
  TestEntry({
    required this.file,
    required this.line,
    required this.groups,
    required this.name,
    required this.isDynamic,
    this.reason,
  });

  final String file;
  final int line;
  final List<String> groups;
  final String? name; // 静的に解決できた名前（動的ならnull）
  final bool isDynamic;
  final String? reason;

  String get fullName => [...groups, name ?? '<dynamic>'].join(' > ');

  Map<String, Object?> toJson() => {
        'file': file,
        'line': line,
        'fullName': fullName,
        'dynamic': isDynamic,
        if (reason != null) 'reason': reason,
      };
}

List<TestEntry> _enumerateFile(File file) {
  final result = parseString(
    content: file.readAsStringSync(),
    featureSet: FeatureSet.latestLanguageVersion(),
    path: file.path,
    throwIfDiagnostics: false,
  );
  final visitor = _TestVisitor(file.path, result.lineInfo);
  result.unit.visitChildren(visitor);
  return visitor.entries;
}

class _TestVisitor extends RecursiveAstVisitor<void> {
  _TestVisitor(this.filePath, this.lineInfo);

  final String filePath;
  final dynamic lineInfo;
  final entries = <TestEntry>[];
  final _groupStack = <String>[];
  final _constStrings = <String, String>{};

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    // ファイル内のconst String宣言を収集（単純な補間の解決に使う）
    for (final variable in node.variables.variables) {
      final initializer = variable.initializer;
      if (initializer is StringLiteral && initializer.stringValue != null) {
        _constStrings[variable.name.lexeme] = initializer.stringValue!;
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    if (method == 'endevirGroup') {
      final label = _resolveString(node.argumentList.arguments.first);
      _groupStack.add(label ?? '<dynamic group>');
      node.argumentList.accept(this);
      _groupStack.removeLast();
      return;
    }
    if (method == 'endevirTest') {
      final nameArg = node.argumentList.arguments.first;
      final name = _resolveString(nameArg);
      final inLoop = node.thisOrAncestorMatching((n) =>
              n is ForStatement || n is WhileStatement || n is DoStatement) !=
          null;
      final line = lineInfo.getLocation(node.offset).lineNumber as int;
      entries.add(TestEntry(
        file: filePath,
        line: line,
        groups: List.of(_groupStack),
        name: name,
        isDynamic: name == null || inLoop,
        reason: name == null
            ? 'テスト名が文字列リテラルとして解決できない'
            : (inLoop ? 'ループ内で宣言されている' : null),
      ));
      return;
    }
    super.visitMethodInvocation(node);
  }

  /// 文字列リテラル（ファイル内const参照の単純な補間を含む）を解決する。
  String? _resolveString(Expression expression) {
    if (expression is SimpleStringLiteral) return expression.value;
    if (expression is AdjacentStrings) {
      final parts = expression.strings.map(_resolveString).toList();
      return parts.contains(null) ? null : parts.join();
    }
    if (expression is StringInterpolation) {
      final buffer = StringBuffer();
      for (final element in expression.elements) {
        if (element is InterpolationString) {
          buffer.write(element.value);
        } else if (element is InterpolationExpression) {
          final inner = element.expression;
          if (inner is SimpleIdentifier &&
              _constStrings.containsKey(inner.name)) {
            buffer.write(_constStrings[inner.name]);
          } else {
            return null; // 解決不能な補間
          }
        }
      }
      return buffer.toString();
    }
    if (expression is SimpleIdentifier &&
        _constStrings.containsKey(expression.name)) {
      return _constStrings[expression.name];
    }
    return null;
  }
}

/// 静的テスト名 → 「対象を1件に絞ってファイルmainを実行する」クロージャの
/// マップを持つテストバンドルを生成する（ネイティブ写像の実行単位）。
String _generateBundle(
  String dirPath,
  List<File> files,
  List<TestEntry> entries,
) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED by tool/s2_enumerate.dart - DO NOT EDIT')
    ..writeln('// ignore_for_file: type=lint')
    ..writeln("import 'package:example_app/endevir_stub.dart';");

  final aliases = <String, String>{};
  for (final file in files) {
    final alias =
        file.uri.pathSegments.last.replaceAll('.dart', '').replaceAll('-', '_');
    aliases[file.path] = alias;
    final relative = file.path.replaceFirst('$dirPath/', '');
    buffer.writeln("import '$relative' as $alias;");
  }

  buffer
    ..writeln()
    ..writeln('/// 静的に列挙されたテスト名 → 実行クロージャ')
    ..writeln('final Map<String, Future<void> Function()> testEntries = {');
  for (final entry in entries.where((e) => !e.isDynamic)) {
    final alias = aliases[entry.file];
    // 注: mainはvoid（登録のみ）。実行はrunBundleEntryが担う（ADR-005）
    buffer.writeln(
      "  '${entry.fullName.replaceAll("'", r"\'")}': () =>"
      " runBundleEntry('${entry.name!.replaceAll("'", r"\'")}', $alias.main),",
    );
  }
  buffer.writeln('};');
  return buffer.toString();
}
