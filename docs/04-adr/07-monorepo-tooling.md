# ADR-007: モノレポはDart pub workspacesで管理する（melosは導入しない）

- 日付: 2026-07-17
- ステータス: Accepted
- 関連: NFR-301、M1（モノレポ初期化）

## 背景・課題

モノレポ（packages/endevir, endevir_reporter, endevir_cli, examples/flutter_app, 将来のapps/）の依存解決とタスク実行の管理方式を決める。候補はDart公式のpub workspaces（Dart 3.6+）と、Flutterモノレポの定番だったmelos。

## 検討した選択肢

### 案A: pub workspaces（採用）

- Dart 3.11（Flutter 3.41同梱）でネイティブサポート。ルートpubspecの `workspace:` + 各メンバーの `resolution: workspace` のみで、**単一のlockfile・単一の依存解決**になる
- 追加ツールのインストール不要（導入時間最短、NFR-001の思想と整合）
- 検証済み: 4パッケージのワークスペース解決・`flutter analyze`・`flutter test` が問題なく動作
- 弱点: タスクランナー機能（全パッケージ一括テスト等）はない → 当面はルートのpackage.jsonスクリプト（既存のpnpm運用）とCIのマトリクスで代替

### 案B: melos

- スクリプト実行・バージョニング・publish管理が充実。melos 7はpub workspacesの上に載る
- 現段階（パッケージ4個、publishはまだ先）では過剰。必要になった時点（publish自動化・changelog管理）で後から追加してもpub workspacesと共存できる

## 決定

pub workspacesのみで開始する。melosはP2（publish運用開始）前に再評価する。

## 影響

- ルート `pubspec.yaml` がワークスペース定義を持つ。メンバー追加時は `workspace:` への追記+`resolution: workspace` が必要
- lockfileはルートに一本化される（メンバーごとのpubspec.lockは廃止）
- 見直しトリガー: パッケージ数の増加でタスク実行・publish管理が煩雑になった時（melos追加を検討）
