// S2/S6スパイク: グループありテスト + 意図的な失敗テスト（失敗伝搬の検証用）
import 'package:example_app/endevir_stub.dart';

void main() {
  endevirGroup('ログイン', () {
    endevirTest('正しい認証情報でログインできる', (e) async {
      await e.expectText('Endevir Example');
    });
    // 意図的に失敗するテスト: ネイティブ側へ失敗が正しく伝搬することを検証する
    endevirTest('誤ったパスワードでエラーが表示される', (e) async {
      await e.expectText('存在しないエラーメッセージ',
          timeout: const Duration(seconds: 2));
    });
  });

  endevirTest('未ログインでもホームを閲覧できる', (e) async {
    await e.expectText('Endevir Example');
  });
}
