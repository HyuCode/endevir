# ADR-006: Android写像はマニフェスト駆動のParameterized JUnit + エージェント実行で行う

- 日付: 2026-07-17
- ステータス: Accepted
- 関連: CORE-109、S6スパイク、[Kotlinテスト](../../examples/flutter_app/android/app/src/androidTest/kotlin/dev/endevir/example_app/EndevirNativeMappingTest.kt) / [エントリポイント](../../examples/flutter_app/endevir_test/main_s6_native.dart)、[[02-agent-transport]]、[[05-static-test-enumeration]]

## 背景・課題

ネイティブテスト写像（1 Dartテスト=1ネイティブテストケース、CORE-109)は、既存デバイスファーム・シャーディング・リトライ基盤に乗るための鍵。PatrolはJUnitランナーが起動時にDart側へテスト階層を問い合わせる（ドライラン同期）が、ADR-005の静的列挙によりこの同期を廃した、より単純な構造が成立するかを検証した。

## 検証結果（S6スパイク、Androidエミュレータ / connectedDebugAndroidTest）

構造: ビルド時マニフェスト（androidTest assets）→ Parameterized JUnitがテストケースを生成 → 各ケースがアプリ内エージェント（ADR-002）の `/runTest?name=` を呼び、Dartテストが実UIを操作 → 結果がJUnitに返る。

| 検証項目                                         | 結果                                                                                                                             |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| マニフェスト→ネイティブテストケース生成          | ✅ 5件のDartテストが `runDartTest[ログイン > 正しい認証情報でログインできる]` 形式のネイティブケースとして個別に実行・報告される |
| Dartテストの実UI操作（タップ・イベント駆動待機） | ✅ 4/4パス（ホーム検証、画面遷移+カウントアップ等）                                                                              |
| 失敗の伝搬                                       | ✅ 意図的な失敗テスト1件のみが失敗し、**Dart側のエラー詳細（TimeoutException+待機対象+所要時間）がJUnitレポートに載る**          |
| ドライラン同期なし                               | ✅ 起動時のDart側への階層問い合わせは不要（Patrolの「最もトリッキーな部分」を排除）                                              |
| スイート全体                                     | 5テスト24秒（アプリ再起動時間を含む）                                                                                            |

## 決定

- Android写像は「**静的マニフェスト（ADR-005）→ Parameterized JUnit → エージェント `/runTest`（ADR-002）**」の構造で実装する
- テスト実行APKは生成コード（マニフェスト・バンドル）とともに `endevir_cli` がビルドする。`-Ptarget` でエントリポイントを注入する（FTL持ち込みと同じ流儀）

## スパイクで得た副次的発見（endevir doctor / CLI設計への入力）

実環境の落とし穴が4つ見つかった。いずれも「Patrolのセットアップが複雑」の正体の一部であり、`endevir init/doctor`（CLI-001/002）が自動処理すべき項目。

1. **JDKバージョン**: ホストのJAVA_HOME（Java 25）でgradleを直接叩くとKotlinコンパイラが落ちる。Flutterが設定するJDK（この環境ではJava 17）をCLIが検出してgradle実行に引き回す必要がある
2. **androidx.testのバージョン制約**: Flutterのdebug embeddingが `androidx.test:runner:1.2.0` を strictly で持ち込み、新しいandroidx.testと衝突する（AGPのconsistent resolution）。バージョンを合わせる必要がある
3. **exported要件**: 古いandroidx.test:coreのマニフェストがtargetSdk 31+の `android:exported` 明示要件を満たさず、androidTestマニフェストでの上書きが必要
4. **MonitoringInstrumentationのActivity管理**: AndroidJUnitRunnerは管理外に起動されたActivityを終了させるため、テストケース側に**エージェント死活確認+自己回復起動**（shell権限の `am start`。通常のstartActivityはAPI 29+のバックグラウンド起動制限で握り潰されうる）を組み込んだ。本実装ではアプリ再起動をテスト分離（クリーンな状態で開始）として積極的に位置づける

## 制約・未検証

- iOS（XCUITest）写像は同じ構造の適用可能性が高いが未検証（P1）
- Firebase Test Labでの実行はM6で確認する（instrumentation形式のため原理的には可能）
- スパイクのHTTP/1.1手書きクライアントはchunked encodingを正しく処理していない（本実装はADR-002のWebSocket+JSON-RPCに置き換わるため問題にしない）
- テストごとのアプリ再起動は分離性と引き換えに時間コストがある（5テスト24秒）。「再起動あり/なし」を選択可能にする設計をM1で検討

## 影響

- CORE-109（Android）の実装方式が確定し、M0の全スパイクが完了
- `endevir doctor` の診断項目リストに上記4つの落とし穴を登録する
- 見直しトリガー: FTL実行（M6）で instrumentation の挙動が異なる場合
