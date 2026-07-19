# ADR-008: テスト契約と実行エンジンを分離し、user-pathを明示分類する

- 日付: 2026-07-19
- ステータス: Accepted
- 関連: [ADR-002](./02-agent-transport.md)、[ADR-006](./06-native-test-mapping.md)

## 背景・課題

Endevirのテストコードはアプリ内エージェントと同じFlutterプロセスで動く。この構成は
高速な自動待機と詳細な証跡に適する一方、テストからState、service、callbackへ直接触れ
られる。したがって、UIを通らない内部操作を含む成功を、利用者経路のE2E成功と同一視
してはならない。

`endevir native android`も、DartテストをParameterized JUnitへ写像してアプリ内
エージェントを呼ぶ仕組みであり、コンパイル済みアプリを外部から操作するblack-box
ドライバーではない。

## 検討した選択肢

### モードを区別せず、すべてE2Eと呼ぶ

APIは単純だが、内部callback呼び出しやfake serviceへの直接操作を利用者経路の証拠と
誤認させる。レポートだけでは保証境界を監査できないため採用しない。

### 現行エンジンを廃止し、PatrolまたはMaestroへ全面移行する

system UI操作やblack-boxに近い経路を早く得られる可能性はある。しかし、Endevir固有の
イベント駆動待機、actionability診断、trace契約を外部ランナーのライフサイクルへ
従属させる。現行機能を置き換える判断としては範囲が大きいため採用しない。

### テスト契約を分類し、実行エンジンとは別に記録する

現行の速度と診断能力を維持しつつ、各成功が何を保証するかをAPI、trace、HTMLレポート
で明示できる。将来の外部ドライバーも同じ分類軸へ追加できる。

## 決定

- 公開APIに`EndevirTestMode.inProcess`と`EndevirTestMode.userPath`を追加する
- 既存テストを暗黙に格上げしないため、既定値は`inProcess`とする
- `userPath`ではシナリオの進行と検証を、描画済みUIに対するEndevirの公開操作APIだけ
  で行う。State/Provider/DB/serviceの直接変更、callbackの直接呼び出し、テスト専用fake
  の呼び出しをシナリオ操作として使わない
- テスト前のfixture投入や状態初期化は許容するが、シナリオ本体と分離し、成功条件の
  代替にしない
- test modeをtraceの`testStart.testMode`へ記録し、HTMLレポートへ表示する。これは
  optional fieldの追加なのでtrace schema v1を維持する
- セレクターは、外部ドライバーでも安定して表現できるSemantics identifier/label、
  in-processで安定する`ValueKey`、完全一致の表示テキスト、scope付きwidget typeの順を
  基本とする。部分一致と正規表現は意図を明示した場合だけ使う
- `endevir native`はネイティブのテストケース・レポートへの写像を表す名称であり、
  black-box操作を意味しない

## native / system UIの方針

OS権限ダイアログ、共有シート、通知などは、アプリ内エージェントだけでは保証できない。
将来のblack-box実行はUIAutomator/XCUITestを薄いプラットフォームドライバーとして
別エンジンに追加する方向を第一候補とする。これによりtraceと診断の主導権を保つ。
Maestroとの相互運用は外部フォールバックとして検証し、Patrol互換APIは設けない。

本番実装の前に、Androidの権限ダイアログとiOS/Androidの共有シートを対象にスパイクし、
操作成功率、診断可能性、保守コストを比較する。スパイクで不利と判明した場合は、この
方針を新しいADRで見直す。

## 影響

- αで保証するのは`inProcess`と明示的な`userPath`まで。外部black-boxとsystem UI操作は
  非対応として公開ドキュメントに記載する
- レビュー時は`userPath`テスト内の直接callback、状態変更、service/fake呼び出しを
  モード違反として扱う
- 将来black-boxモードを追加する場合も、実行エンジン名と保証境界を混同しない
