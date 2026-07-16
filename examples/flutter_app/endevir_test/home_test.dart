// S2スパイク: 静的列挙の検証対象テストファイル（動的なテスト名を含む）
import 'package:example_app/endevir_stub.dart';

const _feature = 'ホーム';

void main() {
  endevirTest('$_feature画面が表示される', (e) async {});

  endevirTest('カウントアップできる', (e) async {});

  // 静的に解決できないテスト名（ループ生成）——列挙器が検出・警告すべきケース
  for (final tab in ['一覧', '詳細']) {
    endevirTest('タブ「$tab」を開ける', (e) async {});
  }
}
