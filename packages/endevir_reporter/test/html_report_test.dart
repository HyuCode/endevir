import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:test/test.dart';

void main() {
  TraceModel model({String testName = 'ログインできる', String? error}) {
    final lines = <String>[];
    var timeUs = 0;
    final writer = TraceWriter(lines.add, nowUs: () => timeUs += 1000);
    writer.runStart(runId: 'run-1', platform: 'ios');
    final testId = writer.testStart(testName);
    final stepId = writer.stepStart('手順A', testId: testId);
    writer.stepEnd(stepId,
        error == null ? TraceStatus.PASSED : TraceStatus.FAILED,
        error: error);
    writer.testEnd(testId,
        error == null ? TraceStatus.PASSED : TraceStatus.FAILED,
        error: error);
    writer.runEnd();
    return TraceModel.fromEvents(lines.map(traceEventFromJson).toList());
  }

  group('buildHtmlReport', () {
    test('テスト名・ステップ名・ステータス・サマリーを含む自己完結HTMLを生成する', () {
      final html = buildHtmlReport(model());

      expect(html, contains('<!doctype html>'));
      expect(html, contains('ログインできる'));
      expect(html, contains('手順A'));
      expect(html, contains('passed'));
      expect(html, contains('run-1'));
      // 外部リソース参照なし（自己完結、RPT-201）
      expect(html, isNot(contains('http://')));
      expect(html, isNot(contains('https://')));
    });

    test('失敗テストはエラー詳細を表示する', () {
      final html = buildHtmlReport(model(error: 'TimeoutException: boom'));

      expect(html, contains('failed'));
      expect(html, contains('TimeoutException: boom'));
    });

    test('スクリーンショットはdata URIとして埋め込まれる（自己完結、RPT-201）', () {
      final lines = <String>[];
      var timeUs = 0;
      final writer = TraceWriter(lines.add, nowUs: () => timeUs += 1000);
      writer.runStart(runId: 'r', platform: 'ios');
      final testId = writer.testStart('t');
      final stepId = writer.stepStart('s', testId: testId);
      writer.stepEnd(stepId, TraceStatus.PASSED, screenshot: 'shots/1.png');
      writer.testEnd(testId, TraceStatus.PASSED);
      writer.runEnd();
      final withShot =
          TraceModel.fromEvents(lines.map(traceEventFromJson).toList());

      final html = buildHtmlReport(
        withShot,
        resolveScreenshot: (path) =>
            path == 'shots/1.png' ? [137, 80, 78, 71] : null,
      );

      expect(html, contains('<img'));
      expect(html, contains('data:image/png;base64,iVBORw=='));
    });

    test('解決できないスクリーンショットはパス表示にフォールバックする', () {
      final lines = <String>[];
      var timeUs = 0;
      final writer = TraceWriter(lines.add, nowUs: () => timeUs += 1000);
      writer.runStart(runId: 'r', platform: 'ios');
      final testId = writer.testStart('t');
      final stepId = writer.stepStart('s', testId: testId);
      writer.stepEnd(stepId, TraceStatus.PASSED, screenshot: 'shots/1.png');
      writer.testEnd(testId, TraceStatus.PASSED);
      writer.runEnd();
      final withShot =
          TraceModel.fromEvents(lines.map(traceEventFromJson).toList());

      final html = buildHtmlReport(withShot);

      expect(html, isNot(contains('<img')));
      // パスがテキストとして表示される（/はHTMLエスケープされる）
      expect(html, contains('1.png'));
    });

    test('テスト名やエラー内のHTMLはエスケープされる（XSS対策）', () {
      final html = buildHtmlReport(
        model(testName: '<script>alert(1)</script>', error: '<b>err</b>'),
      );

      expect(html, isNot(contains('<script>alert(1)</script>')));
      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('<b>err</b>')));
    });
  });
}
