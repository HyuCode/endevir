// S2スパイク: 静的列挙の検証対象テストファイル（グループあり）
import 'package:example_app/endevir_stub.dart';

void main() {
  endevirGroup('ログイン', () {
    endevirTest('正しい認証情報でログインできる', (e) async {});
    endevirTest('誤ったパスワードでエラーが表示される', (e) async {});
  });

  endevirTest('未ログインでもホームを閲覧できる', (e) async {});
}
