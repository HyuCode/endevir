# Endevir Reporter

Endevir Reporter provides the language-neutral trace model, JSONL writer,
runtime protocol messages, and self-contained HTML evidence report used by
Endevir test runs.

The package is pure Dart. It can be used by runners, CI integrations, and
custom report tooling without depending on Flutter.

## Features

- Versioned trace events generated from the repository JSON Schema
- Monotonic sequence numbers and timestamps
- Test, attempt, step, screenshot, and log correlation
- Structured `TraceModel` for downstream viewers
- Self-contained HTML with inline screenshots
- Horizontal storyboard presentation for mobile test steps

## Usage

Record trace events as JSONL:

```dart
import 'package:endevir_reporter/endevir_reporter.dart';

final lines = <String>[];
final writer = TraceWriter(lines.add);

writer.runStart(runId: 'run-1', platform: 'android');
final testId = writer.testStart('opens the home screen');
final stepId = writer.stepStart('Launch', testId: testId);
writer.stepEnd(stepId, TraceStatus.PASSED);
writer.testEnd(testId, TraceStatus.PASSED);
writer.runEnd();
```

Parse trace events into a `TraceModel`, then pass it to `buildHtmlReport`.
When `resolveScreenshot` returns PNG bytes, the report embeds them as data
URIs and remains a single shareable file.

The schema source lives at
[`schema/trace_event.schema.json`](https://github.com/HyuCode/endevir/blob/main/schema/trace_event.schema.json).
Generated types must be updated with `pnpm codegen` in the repository root.
