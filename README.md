# Endevir

Flutter向けのAIネイティブE2Eテストフレームワーク。**flakyでない自動待機・手順+スクリーンショットの実行証跡・数秒の開発イテレーション**を核に、Apache-2.0のOSSとして開発中。

> M0〜M6の実装を完了し、最初のα公開を準備しています。API・スキーマは
> stableリリースまで予告なく変わる可能性があります。

## 何ができるか（現時点）

```dart
// endevir_test/main_test.dart
import 'package:endevir/endevir.dart';
import 'package:example_app/main.dart';

Future<void> main() => endevirRunnerMain(
      registerTests: () {
        endevirTest(
          'カウントアップできる',
          (e) async {
            await e.step('画面遷移', () => e.$(#nav_button).tap());
            await e.expectVisible('カウント: 1');
          },
          mode: EndevirTestMode.userPath,
        );
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

For repeated device runs, build once and reuse the validated artifact:

```console
dart run endevir_cli:endevir_cli build -p ios
dart run endevir_cli:endevir_cli test -p ios -d <simulator-udid> --reuse-build
```

Endevir fingerprints source, tests, assets, dependencies, and native project
inputs. A stale or missing artifact is rejected instead of being run silently.

- タップはイベント駆動の自動待機+位置安定チェック（exists≠actionable対策）つき
- 実行は全ステップがtrace（JSONL）として記録され、自己完結HTMLレポートが生成される
- iOSシミュレータ / Androidエミュレータ・実機に同一コマンドで対応

## テストが保証する境界

Endevirの現行ランナーは、テストコードとアプリを同じFlutterプロセスで動かす。
テスト結果を過大評価しないため、各テストは操作境界を分類する。

| モード      | 契約                                                                                            |
| ----------- | ----------------------------------------------------------------------------------------------- |
| `inProcess` | State、service、callbackなどアプリ内部への直接アクセスを許容する。既定値                        |
| `userPath`  | 公開UIの検索・入力・表示検証だけでシナリオを進める。`mode: EndevirTestMode.userPath` を明示する |

`userPath`も実行エンジンはin-processであり、コンパイル済みアプリを外部から操作する
black-boxテストではない。OS権限ダイアログ、共有シート、通知などのシステムUI操作は
α時点では非対応。`endevir native android` はJUnitへのケース写像であり、この境界を
black-boxへ変更しない。詳細は[ADR-008](docs/01-adr/08-test-mode-boundary.md)を参照。

## モノレポ構成

| パス                        | 内容                                                                                                                                                                                  |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/endevir`          | テスト記述API・ランナー・待機・アプリ内エージェント（Flutter）                                                                                                                        |
| `packages/endevir_reporter` | traceスキーマ型・TraceWriter・HTMLレポート（pure Dart）                                                                                                                               |
| `packages/endevir_cli`      | init・doctor・test・develop・Android instrumentation CLI                                                                                                                              |
| `examples/flutter_app`      | 検証用アプリ（M0スパイクの成果物を含む）                                                                                                                                              |
| `schema/`                   | trace/プロトコルのJSON Schema（単一の真実、`pnpm codegen` で型生成）                                                                                                                  |
| `docs/`                     | [ADR](docs/01-adr/README.md) / [設計](docs/02-design/01-trace-schema.md) / [ベンチマーク](docs/03-benchmarks/01-mvp-benchmarks.md) / [Cloud連携契約](docs/04-integration/01-cloud.md) |

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

原則TDD。技術決定は[ADR](docs/01-adr/README.md)に記録する。

## 関連リポジトリ

Endevir Cloudの公式サイト・ダッシュボード・実行基盤は別リポジトリで
開発しています。公開される連携境界は
[Cloud integration contract](docs/04-integration/01-cloud.md)を参照してください。

## ライセンス

Apache License 2.0。詳細は[LICENSE](LICENSE)を参照してください。
