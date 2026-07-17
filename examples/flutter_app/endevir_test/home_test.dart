// S2/S6スパイク: 実UIを操作するテスト（+動的なテスト名の検出ケース）
import 'package:example_app/endevir_stub.dart';

const _feature = 'ホーム';

void main() {
  endevirTest('$_feature画面が表示される', (e) async {
    await e.expectText('Endevir Example');
  });

  endevirTest('カウントアップできる', (e) async {
    await e.tap('nav_infinite_animation');
    await e.expectText('カウント: 0');
    await e.tap('increment_button');
    await e.expectText('カウント: 1');
  });

  // 静的に解決できないテスト名（ループ生成）——列挙器が検出・警告すべきケース
  for (final tab in ['一覧', '詳細']) {
    endevirTest('タブ「$tab」を開ける', (e) async {});
  }
}
