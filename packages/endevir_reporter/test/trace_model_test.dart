import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:test/test.dart';

void main() {
  /// TraceWriterで実traceと同じ形のイベント列を作る。
  List<TraceEvent> buildTrace() {
    final lines = <String>[];
    var timeUs = 0;
    final writer = TraceWriter(lines.add, nowUs: () => timeUs += 1000);

    writer.runStart(runId: 'run-1', platform: 'ios');
    final test1 = writer.testStart('ログインできる');
    final step1 = writer.stepStart('入力する', testId: test1);
    writer.log(LogSource.DART, 'typing', stepId: step1);
    writer.stepEnd(step1, TraceStatus.PASSED, screenshot: 'shots/1.png');
    writer.testEnd(test1, TraceStatus.PASSED);
    final test2 = writer.testStart('落ちるテスト');
    final step2 = writer.stepStart('壊れる手順', testId: test2);
    writer.stepEnd(step2, TraceStatus.FAILED, error: 'boom');
    writer.testEnd(test2, TraceStatus.FAILED, error: 'boom');
    writer.runEnd();

    return lines.map(traceEventFromJson).toList();
  }

  group('TraceModel.fromEvents', () {
    test('run情報とテスト・ステップ・ログが構造化される', () {
      final model = TraceModel.fromEvents(buildTrace());

      expect(model.runId, 'run-1');
      expect(model.platform, 'ios');
      expect(model.tests, hasLength(2));

      final test1 = model.tests[0];
      expect(test1.name, 'ログインできる');
      expect(test1.status, TraceStatus.PASSED);
      expect(test1.steps, hasLength(1));
      expect(test1.steps[0].name, '入力する');
      expect(test1.steps[0].screenshot, 'shots/1.png');
      expect(test1.steps[0].logs, hasLength(1));
      expect(test1.steps[0].logs[0].message, 'typing');

      final test2 = model.tests[1];
      expect(test2.status, TraceStatus.FAILED);
      expect(test2.error, 'boom');
      expect(test2.steps[0].status, TraceStatus.FAILED);
      expect(test2.steps[0].error, 'boom');
    });

    test('集計（passed/failed）が取れる', () {
      final model = TraceModel.fromEvents(buildTrace());

      expect(model.total, 2);
      expect(model.passed, 1);
      expect(model.failed, 1);
    });

    test('durationがイベントから引き継がれる', () {
      final model = TraceModel.fromEvents(buildTrace());

      expect(model.tests[0].durationUs, greaterThan(0));
      expect(model.tests[0].steps[0].durationUs, greaterThan(0));
    });
  });
}
