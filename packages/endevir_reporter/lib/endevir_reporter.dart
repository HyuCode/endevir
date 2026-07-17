/// Endevir Reporter: trace（実行証跡）の記録・読み取り・レポート生成。
///
/// traceスキーマは schema/trace_event.schema.json が単一の真実であり、
/// 型は `pnpm codegen` で生成される（RPT-006）。
library;

export 'src/generated/trace_event.g.dart';
export 'src/trace_writer.dart';
