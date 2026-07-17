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

        endevirTest('カウントアップできる', (e) async {
          await e.step('無限アニメーション画面へ遷移', () async {
            await e.$(#nav_infinite_animation).tap();
            await e.expectVisible('カウント: 0');
          });
          await e.step('カウントアップ', () async {
            await e.$(#increment_button).tap();
          });
          await e.step('カウント表示を検証', () async {
            await e.expectVisible('カウント: 1');
          });
        });
      },
      appBuilder: () => const ExampleApp(),
    );
