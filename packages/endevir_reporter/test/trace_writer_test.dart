import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:test/test.dart';

void main() {
  late List<String> lines;
  late int currentTimeUs;
  late TraceWriter writer;

  List<TraceEvent> parsed() =>
      lines.map((line) => traceEventFromJson(line)).toList();

  setUp(() {
    lines = [];
    currentTimeUs = 1_000_000;
    writer = TraceWriter(lines.add, nowUs: () => currentTimeUs);
  });

  group('TraceWriter', () {
    test('run/test/step/logの一連のイベントがJSONLとして書かれ、生成型で読み戻せる', () {
      writer.runStart(runId: 'run-1', platform: 'android');
      final testId = writer.testStart('ログインできる');
      final stepId = writer.stepStart('ログインボタンをタップ', testId: testId);
      writer.log(LogSource.DART, 'tapped', stepId: stepId);
      writer.stepEnd(stepId, TraceStatus.PASSED, screenshot: 'shots/1.png');
      writer.testEnd(testId, TraceStatus.PASSED);
      writer.runEnd();

      final events = parsed();
      expect(events.map((e) => e.type).toList(), [
        TraceEventType.RUN_START,
        TraceEventType.TEST_START,
        TraceEventType.STEP_START,
        TraceEventType.LOG,
        TraceEventType.STEP_END,
        TraceEventType.TEST_END,
        TraceEventType.RUN_END,
      ]);
    });

    test('seqは全イベントを通じて厳密に単調増加する', () {
      writer.runStart(runId: 'run-1', platform: 'ios');
      final testId = writer.testStart('t');
      final stepId = writer.stepStart('s', testId: testId);
      writer.stepEnd(stepId, TraceStatus.PASSED);
      writer.runEnd();

      final seqs = parsed().map((e) => e.seq).toList();
      for (var i = 1; i < seqs.length; i++) {
        expect(seqs[i], greaterThan(seqs[i - 1]));
      }
    });

    test('runStartはschemaVersionとrunId・platform・timestampUsを持つ', () {
      writer.runStart(runId: 'run-42', platform: 'android');

      final event = parsed().single;
      expect(event.schemaVersion, '1');
      expect(event.runId, 'run-42');
      expect(event.platform, 'android');
      expect(event.timestampUs, 1_000_000);
    });

    test('stepEndは注入クロックに基づくdurationUsを持つ', () {
      writer.runStart(runId: 'r', platform: 'android');
      final testId = writer.testStart('t');
      currentTimeUs = 2_000_000;
      final stepId = writer.stepStart('s', testId: testId);
      currentTimeUs = 2_750_000;
      writer.stepEnd(stepId, TraceStatus.FAILED, error: 'boom');

      final stepEnd = parsed().last;
      expect(stepEnd.type, TraceEventType.STEP_END);
      expect(stepEnd.durationUs, 750_000);
      expect(stepEnd.status, TraceStatus.FAILED);
      expect(stepEnd.error, 'boom');
    });

    test('testEndはtestStartからのdurationUsを持つ', () {
      writer.runStart(runId: 'r', platform: 'android');
      currentTimeUs = 3_000_000;
      final testId = writer.testStart('t');
      currentTimeUs = 4_500_000;
      writer.testEnd(testId, TraceStatus.PASSED);

      final testEnd = parsed().last;
      expect(testEnd.durationUs, 1_500_000);
      expect(testEnd.testId, testId);
    });

    test('logはstepId相関とsourceを持つ（stepId省略も可）', () {
      writer.runStart(runId: 'r', platform: 'android');
      final testId = writer.testStart('t');
      final stepId = writer.stepStart('s', testId: testId);
      writer.log(LogSource.NETWORK, 'GET /api', stepId: stepId);
      writer.log(LogSource.RUNNER, 'suite info');

      final logs = parsed().where((e) => e.type == TraceEventType.LOG).toList();
      expect(logs[0].stepId, stepId);
      expect(logs[0].source, LogSource.NETWORK);
      expect(logs[0].message, 'GET /api');
      expect(logs[1].stepId, isNull);
    });

    test('testStart/testEndはattempt（試行番号）を記録する', () {
      writer.runStart(runId: 'r', platform: 'android');
      final testId = writer.testStart('flakyなテスト', attempt: 2);
      writer.testEnd(testId, TraceStatus.PASSED, attempt: 2);

      final events = parsed();
      expect(events[1].attempt, 2);
      expect(events[2].attempt, 2);
    });

    test('testStartはテストの操作境界を記録する', () {
      writer.runStart(runId: 'r', platform: 'android');
      writer.testStart('ユーザーパス', mode: TraceTestMode.USER_PATH);

      expect(parsed()[1].testMode, TraceTestMode.USER_PATH);
    });

    test('attempt省略時は1（初回試行）になる', () {
      writer.runStart(runId: 'r', platform: 'android');
      final testId = writer.testStart('t');
      writer.testEnd(testId, TraceStatus.PASSED);

      expect(parsed()[1].attempt, 1);
      expect(parsed()[2].attempt, 1);
    });

    test('複数ステップでstepIdが一意に採番される', () {
      writer.runStart(runId: 'r', platform: 'android');
      final testId = writer.testStart('t');
      final step1 = writer.stepStart('s1', testId: testId);
      writer.stepEnd(step1, TraceStatus.PASSED);
      final step2 = writer.stepStart('s2', testId: testId);
      writer.stepEnd(step2, TraceStatus.PASSED);

      expect(step1, isNot(step2));
      final stepStarts = parsed()
          .where((e) => e.type == TraceEventType.STEP_START)
          .toList();
      expect(stepStarts.map((e) => e.stepId), [step1, step2]);
    });
  });
}
