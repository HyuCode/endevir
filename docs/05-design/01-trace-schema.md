# 設計: traceスキーマ v1

- 日付: 2026-07-17
- 対象要件: RPT-001/002/006、ADR-004
- 実体: [schema/trace_event.schema.json](../../schema/trace_event.schema.json)（単一の真実）

## 形式

traceは**JSONL**（1行=1イベント）+ 添付ファイル（スクリーンショット等は相対パス参照）。イベントは `TraceEvent` 単一型で、`type` 判別子（runStart / testStart / stepStart / stepEnd / log / testEnd / runEnd）を持つフラット構造。

## 設計判断

1. **全イベント共通の `seq`（単調増加）+ `timestampUs`（マイクロ秒）**: ステップ相関（RPT-002）の基盤。ログ⇔ステップの双方向参照は `stepId` で行い、時刻はすべて同一時間軸に乗る
2. **フラット構造+type判別（v1）**: quicktypeのDart/TypeScript生成が素直に通る形を優先した。イベント種別ごとの厳密な必須フィールド制約はスキーマ上は表現していない（ライター実装とテストで保証）。種別が増えて煩雑になったらv2でoneOf分割を検討する
3. **enum命名はスキーマの `title` で制御**: `type` プロパティをそのまま生成すると `dart:core.Type` と衝突するため、`TraceEventType` / `TraceStatus` / `LogSource` をスキーマ側で指定
4. **duration・採番はライターの責務**: `TraceWriter`（endevir_reporter）がseq・testId/stepIdの採番とduration計算を行う。時刻はテスト可能性のため注入式

## 生成フロー

```txt
schema/trace_event.schema.json（真実）
  └─ pnpm codegen（scripts/codegen.sh, quicktype）
       ├─ packages/endevir_reporter/lib/src/generated/trace_event.g.dart（Dart: reporter/Mobile）
       └─ schema/generated/typescript/trace_event.ts（TS: Cloud用。別リポジトリへ同期する）
```

生成物は手で編集しない。スキーマ変更時は `pnpm codegen` を再実行してコミットする（CIでの生成差分チェックをM1のCI整備時に追加する）。

## バージョニング

- `runStart` イベントが `schemaVersion`（現在 "1"）を持つ。読み手は未知バージョンを拒否ではなく警告として扱う
- v1系内の変更は**追加のみ**（フィールド削除・意味変更はメジャャーバージョンを上げる）— NFR-303

## 未決（今後の拡張）

- ネットワークイベントの詳細フィールド（メソッド・ステータスコード・所要時間）— BE-008で設計
- 添付ファイルのマニフェスト（trace全体のzip化、ビューアの読み込み単位）— RPT-101ビューア実装時
- Semantics/ウィジェットツリースナップショットの表現 — M5
