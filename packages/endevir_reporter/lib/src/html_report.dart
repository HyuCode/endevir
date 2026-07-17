import 'dart:convert';

import 'generated/trace_event.g.dart';
import 'trace_model.dart';

/// 自己完結HTMLレポートを生成する（RPT-201、証跡ビューの最小版）。
///
/// 外部リソースへの参照を持たず、そのまま共有できる。
/// 手順+結果をステップバイステップで確認できることを優先する（RPT-102の原型）。
/// [resolveScreenshot]がパスに対して画像バイト列を返すと、data URIとして
/// インライン埋め込みされる（自己完結を保つ）。
String buildHtmlReport(
  TraceModel model, {
  List<int>? Function(String path)? resolveScreenshot,
}) {
  final buffer = StringBuffer()
    ..writeln('<!doctype html>')
    ..writeln('<html lang="ja">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>Endevir Report - ${_escape(model.runId)}</title>')
    ..writeln('<style>$_css</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<header>')
    ..writeln('<h1>Endevir Report</h1>')
    ..writeln('<p class="meta">run: ${_escape(model.runId)} / '
        'platform: ${_escape(model.platform)}</p>')
    ..writeln('<p class="summary">'
        '<span class="count">${model.total} tests</span> '
        '<span class="badge passed">${model.passed} passed</span> '
        '<span class="badge failed-badge">${model.failed} failed</span>'
        '</p>')
    ..writeln('</header>');

  for (final test in model.tests) {
    final status = _statusName(test.status);
    buffer
      ..writeln('<details class="test $status" '
          '${status == 'failed' ? 'open' : ''}>')
      ..writeln('<summary>'
          '<span class="status $status">$status</span> '
          '${_escape(test.name)} '
          '<span class="duration">${_formatUs(test.durationUs)}</span>'
          '</summary>');
    if (test.error != null) {
      buffer.writeln('<pre class="error">${_escape(test.error!)}</pre>');
    }
    if (test.steps.isNotEmpty) {
      // 手順は横並びのストーリーボード形式（モバイルの縦長スクリーンショットは
      // 横に並べた方がフローとして追いやすい）
      buffer.writeln('<div class="steps-strip">');
      for (final (index, step) in test.steps.indexed) {
        final stepStatus = _statusName(step.status);
        buffer
          ..writeln('<div class="step-card $stepStatus">')
          ..writeln('<div class="step-head">'
              '<span class="step-index">${index + 1}</span> '
              '<span class="status $stepStatus">$stepStatus</span> '
              '<span class="duration">${_formatUs(step.durationUs)}</span>'
              '</div>')
          ..writeln('<p class="step-name">${_escape(step.name)}</p>');
        if (step.screenshot != null) {
          final bytes = resolveScreenshot?.call(step.screenshot!);
          if (bytes != null) {
            buffer.writeln('<figure class="screenshot">'
                '<img alt="${_escape(step.name)}" loading="lazy" '
                'src="data:image/png;base64,${base64Encode(bytes)}">'
                '</figure>');
          } else {
            buffer.writeln('<p class="screenshot">📸 '
                '${_escape(step.screenshot!)}</p>');
          }
        }
        if (step.error != null) {
          buffer.writeln('<pre class="error">${_escape(step.error!)}</pre>');
        }
        for (final log in step.logs) {
          buffer.writeln('<p class="log">'
              '<span class="source">[${log.source?.name ?? '-'}]</span> '
              '${_escape(log.message)}</p>');
        }
        buffer.writeln('</div>');
      }
      buffer.writeln('</div>');
    }
    buffer.writeln('</details>');
  }

  buffer
    ..writeln('</body>')
    ..writeln('</html>');
  return buffer.toString();
}

String _statusName(TraceStatus? status) => switch (status) {
      TraceStatus.PASSED => 'passed',
      TraceStatus.FAILED => 'failed',
      TraceStatus.SKIPPED => 'skipped',
      null => 'unknown',
    };

String _formatUs(int? us) =>
    us == null ? '' : '${(us / 1000).toStringAsFixed(0)}ms';

String _escape(String text) => const HtmlEscape().convert(text);

const _css = '''
:root { font-family: -apple-system, "Hiragino Sans", sans-serif;
  color: #1a1a2e; background: #f7f7fa; }
body { margin: 0 auto; max-width: 900px; padding: 24px; }
header h1 { margin: 0 0 4px; font-size: 22px; }
.meta { color: #666; margin: 0 0 8px; font-size: 13px; }
.summary { margin: 0 0 16px; }
.badge { padding: 2px 10px; border-radius: 12px; font-size: 13px; }
.badge.passed { background: #d9f2e3; color: #116633; }
.badge.failed-badge { background: #fde2e2; color: #a11a1a; }
.test { background: #fff; border: 1px solid #e3e3ea; border-radius: 8px;
  margin-bottom: 8px; padding: 8px 14px; }
.test summary { cursor: pointer; font-weight: 600; }
.status { display: inline-block; min-width: 56px; text-align: center;
  font-size: 12px; font-weight: 700; border-radius: 4px; padding: 1px 6px; }
.status.passed { background: #d9f2e3; color: #116633; }
.status.failed { background: #fde2e2; color: #a11a1a; }
.status.unknown, .status.skipped { background: #eee; color: #666; }
.duration { color: #999; font-size: 12px; font-weight: 400; }
.steps-strip { display: flex; gap: 12px; overflow-x: auto;
  margin: 12px 0 6px; padding-bottom: 8px; align-items: flex-start; }
.step-card { flex: 0 0 auto; width: 220px; background: #fafafc;
  border: 1px solid #e3e3ea; border-radius: 8px; padding: 10px;
  position: relative; }
.step-card:not(:last-child)::after { content: "→"; position: absolute;
  right: -12px; top: 45%; color: #bbb; font-size: 14px; }
.step-head { display: flex; align-items: center; gap: 6px; }
.step-index { display: inline-flex; align-items: center;
  justify-content: center; width: 20px; height: 20px; border-radius: 50%;
  background: #1a1a2e; color: #fff; font-size: 11px; font-weight: 700; }
.step-name { font-size: 13px; font-weight: 600; margin: 8px 0 6px;
  line-height: 1.4; }
.error { background: #fff5f5; border-left: 3px solid #a11a1a;
  padding: 8px 10px; white-space: pre-wrap; font-size: 12px;
  overflow-wrap: break-word; }
.log { color: #555; font-size: 12px; margin: 2px 0; }
.log .source { color: #999; }
.screenshot { font-size: 12px; color: #555; margin: 8px 0 0; }
.screenshot img { width: 100%; border: 1px solid #e3e3ea;
  border-radius: 6px; display: block; }
''';
