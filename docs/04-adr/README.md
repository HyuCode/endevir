# ADR（アーキテクチャ決定記録）

技術上の重要な決定を番号付きで記録する。M0スパイクの結論はすべてADRとして残す（[MVP計画 §3 M0](../03-plan/01-mvp-plan.md)）。

## 運用ルール

- テンプレートは [00-template.md](./00-template.md) を使用する
- 番号は採番後に変更・再利用しない。決定を覆す場合は新しいADRを起こし、旧ADRのステータスを「Superseded by ADR-XXX」に更新する
- ステータス: Proposed（提案中）→ Accepted（採用）/ Rejected（不採用）/ Superseded（置き換え）

## 一覧

| 番号                                       | タイトル                                                                    | ステータス | 関連              |
| ------------------------------------------ | --------------------------------------------------------------------------- | ---------- | ----------------- |
| [ADR-001](./01-event-driven-waiting.md)    | 自動待機はフレーム終端でのファインダー再評価（イベント駆動）で実装する      | Accepted   | CORE-102 / S3     |
| [ADR-002](./02-agent-transport.md)         | エージェント通信は単一WebSocket常時接続を一次トランスポートにする           | Accepted   | CORE-105 / S1     |
| [ADR-003](./03-hot-restart-loop.md)        | 開発イテレーションはVMサービス経由のホットリスタートで再実行する            | Accepted   | CLI-102 / S5      |
| [ADR-004](./04-trace-recording-cost.md)    | 証跡のスクリーンショットはGPUスナップショットのみ同期、エンコードは遅延する | Accepted   | RPT-001〜006 / S4 |
| [ADR-005](./05-static-test-enumeration.md) | テスト列挙は構文解析による静的抽出で行い、ドライランを廃する                | Accepted   | CORE-110 / S2     |
| [ADR-006](./06-native-test-mapping.md)     | Android写像はマニフェスト駆動のParameterized JUnit + エージェント実行で行う | Accepted   | CORE-109 / S6     |
| [ADR-007](./07-monorepo-tooling.md)        | モノレポはDart pub workspacesで管理する（melosは導入しない）                | Accepted   | NFR-301 / M1      |
