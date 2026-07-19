import '../tester/endevir_tester.dart';

/// テスト本文のシグネチャ。
typedef EndevirTestBody = Future<void> Function(EndevirTester e);

/// テストが保証する操作境界。
///
/// [EndevirTestMode.inProcess]はアプリ内部への直接アクセスを許容する。既存テストを暗黙に
/// E2E相当へ格上げしないため、これを既定値とする。
/// [EndevirTestMode.userPath]は公開UI操作だけでシナリオを進めるテストに明示する。
enum EndevirTestMode { inProcess, userPath }

/// 登録済みテスト。
class EndevirTestEntry {
  const EndevirTestEntry(
    this.name,
    this.body, {
    this.retries,
    this.mode = EndevirTestMode.inProcess,
  });

  /// グループ修飾済みの完全名（静的列挙のfullNameと一致する。ADR-005）。
  final String name;
  final EndevirTestBody body;

  /// テスト単位のリトライ回数（nullなら実行時設定に従う。CORE-103/106）。
  final int? retries;

  /// このテストが保証する操作境界。
  final EndevirTestMode mode;
}

/// テストの登録先（登録と実行の分離、ADR-005）。
class EndevirTestRegistry {
  final List<EndevirTestEntry> _entries = [];
  final List<String> _groupStack = [];

  List<EndevirTestEntry> get entries => List.unmodifiable(_entries);

  /// テストを登録する。実行はランナーの責務。
  void add(
    String name,
    EndevirTestBody body, {
    int? retries,
    EndevirTestMode mode = EndevirTestMode.inProcess,
  }) {
    final fullName = [..._groupStack, name].join(' > ');
    if (_entries.any((entry) => entry.name == fullName)) {
      throw ArgumentError('duplicate test name: $fullName');
    }
    _entries.add(
      EndevirTestEntry(fullName, body, retries: retries, mode: mode),
    );
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
/// [retries]でこのテストだけのリトライ回数を指定できる（CORE-103/106）。
/// [mode]でテストが保証する操作境界を明示する。
/// 既定値は[EndevirTestMode.inProcess]。
void endevirTest(
  String name,
  EndevirTestBody body, {
  int? retries,
  EndevirTestMode mode = EndevirTestMode.inProcess,
}) => endevirRegistry.add(name, body, retries: retries, mode: mode);

/// テストをグループ化する。
void endevirGroup(String name, void Function() body) =>
    endevirRegistry.group(name, body);
