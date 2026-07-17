import '../tester/endevir_tester.dart';

/// テスト本文のシグネチャ。
typedef EndevirTestBody = Future<void> Function(EndevirTester e);

/// 登録済みテスト。
class EndevirTestEntry {
  const EndevirTestEntry(this.name, this.body);

  /// グループ修飾済みの完全名（静的列挙のfullNameと一致する。ADR-005）。
  final String name;
  final EndevirTestBody body;
}

/// テストの登録先（登録と実行の分離、ADR-005）。
class EndevirTestRegistry {
  final List<EndevirTestEntry> _entries = [];
  final List<String> _groupStack = [];

  List<EndevirTestEntry> get entries => List.unmodifiable(_entries);

  /// テストを登録する。実行はランナーの責務。
  void add(String name, EndevirTestBody body) {
    final fullName = [..._groupStack, name].join(' > ');
    if (_entries.any((entry) => entry.name == fullName)) {
      throw ArgumentError('duplicate test name: $fullName');
    }
    _entries.add(EndevirTestEntry(fullName, body));
  }

  /// グループを開いて[body]内の登録名を「group > name」に修飾する。
  void group(String name, void Function() body) {
    _groupStack.add(name);
    try {
      body();
    } finally {
      _groupStack.removeLast();
    }
  }

  void clear() {
    _entries.clear();
    _groupStack.clear();
  }
}

/// グローバルレジストリ（テストファイルのmain()から使う公開API）。
final endevirRegistry = EndevirTestRegistry();

/// テストを宣言する（登録のみ。実行はランナーが行う）。
void endevirTest(String name, EndevirTestBody body) =>
    endevirRegistry.add(name, body);

/// テストをグループ化する。
void endevirGroup(String name, void Function() body) =>
    endevirRegistry.group(name, body);
