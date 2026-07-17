// Endevirテストエントリポイント（M1縦の貫通用）。
// `endevir test` がこのファイルをターゲットにアプリをビルド・起動し、
// エージェント経由でテストを実行してtraceを回収する。
import 'package:endevir/endevir.dart';
import 'package:example_app/main.dart';

Future<void> main() => endevirRunnerMain(
      registerTests: () {
        endevirTest('ホーム画面が表示される', (e) async {
          await e.expectVisible('Endevir Example');
        });

        endevirTest('無限アニメーション下でもカウントアップできる', (e) async {
          await e.step('無限アニメーション画面へ遷移', () async {
            await e.$(#nav_infinite_animation).tap();
            await e.expectVisible('カウント: 0');
          });
          await e.step('カウントアップ', () async {
            await e.$(#increment_button).tap();
          });
          await e.step('カウント表示を検証', () async {
            await e.expectVisible(RegExp(r'カウント: 1'));
          });
        });

        endevirTest('遅延ロード（3秒）をsleepなしで待てる', (e) async {
          await e.step('遅延ロード画面へ遷移', () async {
            await e.$(#nav_delayed_load).tap();
            await e.expectVisible(#loading_indicator);
          });
          await e.step('読み込み完了を待つ', () async {
            await e.expectVisible(#loaded_content);
          });
        });

        endevirTest('有限アニメーションの完了を検証できる', (e) async {
          await e.step('アニメーション画面へ遷移', () async {
            await e.$(#nav_animation).tap();
            await e.expectVisible('アニメーション完了: 0回');
          });
          await e.step('アニメーションを起動して完了を待つ', () async {
            await e.$(#toggle_button).tap();
            await e.expectVisible('アニメーション完了: 1回');
          });
        });

        endevirTest('フォームに入力して送信できる', (e) async {
          await e.step('フォーム画面へ遷移', () async {
            await e.$(#nav_form).tap();
            await e.expectVisible(#email_field);
          });
          await e.step('メールアドレスを入力', () async {
            await e.$(#email_field).enterText('user@example.com');
          });
          await e.step('送信して結果を確認', () async {
            await e.$(#submit_button).tap();
            await e.expectVisible(#submit_result);
          });
        });
      },
      appBuilder: () => const ExampleApp(),
    );
