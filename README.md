# Endevir

Flutter向けのAIネイティブE2Eテストフレームワーク。**flakyでない自動待機・手順+スクリーンショットの実行証跡・数秒の開発イテレーション**を核に、ローカルは完全無償のOSS、マネタイズは有償クラウド実行環境として開発中。

> M0〜M7の実装を完了し、最初のα公開を準備しています。API・スキーマは
> stableリリースまで予告なく変わる可能性があります。

## 何ができるか（現時点）

```dart
// endevir_test/main_test.dart
import 'package:endevir/endevir.dart';
import 'package:example_app/main.dart';

Future<void> main() => endevirRunnerMain(
      registerTests: () {
        endevirTest('カウントアップできる', (e) async {
          await e.step('画面遷移', () => e.$(#nav_button).tap());
          await e.expectVisible('カウント: 1');
        });
      },
      appBuilder: () => const ExampleApp(),
    );
```

```console
$ dart run endevir_cli:endevir_cli test -p ios -d <simulator-udid>
  ホーム画面が表示される ... ok (5ms)
  カウントアップできる ... ok (752ms)
[endevir] 2 tests: 2 passed, 0 failed
[endevir] trace:  .endevir/trace.jsonl
[endevir] report: .endevir/report.html
```

- タップはイベント駆動の自動待機+位置安定チェック（exists≠actionable対策）つき
- 実行は全ステップがtrace（JSONL）として記録され、自己完結HTMLレポートが生成される
- iOSシミュレータ / Androidエミュレータ・実機に同一コマンドで対応

## モノレポ構成

| パス                        | 内容                                                                                                                                                                                    |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/endevir`          | テスト記述API・ランナー・待機・アプリ内エージェント（Flutter）                                                                                                                          |
| `packages/endevir_reporter` | traceスキーマ型・TraceWriter・HTMLレポート（pure Dart）                                                                                                                                 |
| `packages/endevir_cli`      | init・doctor・test・develop・Android instrumentation CLI                                                                                                                                |
| `examples/flutter_app`      | 検証用アプリ（M0スパイクの成果物を含む）                                                                                                                                                |
| `schema/`                   | trace/プロトコルのJSON Schema（単一の真実、`pnpm codegen` で型生成）                                                                                                                    |
| `docs/`                     | [調査](docs/01-reports/README.md) / [要件定義](docs/02-spec/README.md) / [計画](docs/03-plan/01-mvp-plan.md) / [ADR](docs/04-adr/README.md) / [設計](docs/05-design/01-trace-schema.md) |

## 開発

必要: [fvm](https://fvm.app)（Flutterは `.fvmrc` で固定）、[pnpm](https://pnpm.io)

```sh
fvm dart pub get          # ワークスペース解決
fvm flutter analyze packages examples
(cd packages/endevir && fvm flutter test)
(cd packages/endevir_reporter && fvm dart test)
(cd packages/endevir_cli && fvm dart test)
pnpm install && pnpm lint:md && pnpm format:check
pnpm codegen              # スキーマから型を再生成
```

原則TDD（[要件定義 §11.1](docs/02-spec/01-overview.md)）。技術決定は[ADR](docs/04-adr/README.md)に記録する。

## 関連リポジトリ

Endevir Cloudの公式サイト・ダッシュボード・実行基盤は、非公開の
`HyuCode/endevir-cloud` で開発しています。

## ライセンス

Apache License 2.0。詳細は[LICENSE](LICENSE)を参照してください。
