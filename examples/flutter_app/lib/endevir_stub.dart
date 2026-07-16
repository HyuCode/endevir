// M0スパイク S2用のEndevir APIスタブ。
// テスト列挙の静的解析対象として、本物のendevirTestと同じ形のシグネチャを提供する。
import 'dart:async';

typedef EndevirTestCallback = Future<void> Function(EndevirTester e);

/// 本物では PatrolIntegrationTester 相当のテストコンテキスト。
class EndevirTester {
  const EndevirTester();
}

/// 実行対象のテスト名（ネイティブ写像時に1テストだけ実行するためのフィルタ）。
/// nullなら全テストを実行する。
String? endevirTargetTest;

/// テストを宣言する。スパイクでは登録のみ行う。
Future<void> endevirTest(String description, EndevirTestCallback body) async {
  if (endevirTargetTest != null && endevirTargetTest != description) return;
  await body(const EndevirTester());
}

/// テストのグループ化（flutter_testのgroupと同形）。
void endevirGroup(String description, void Function() body) {
  body();
}
