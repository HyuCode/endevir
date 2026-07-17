import 'generated/trace_event.g.dart';

/// traceイベントをJSONLとして書き出すライター（RPT-001/002）。
///
/// - すべてのイベントに単調増加の`seq`と共通時刻軸の`timestampUs`を付与する
/// - `testId`/`stepId`を採番し、ログをステップに相関付けられるようにする
/// - 出力先は行シンク（ファイル・メモリ・ネットワーク）として注入する
/// - 時刻は[nowUs]として注入可能（テストの決定性、ADR-004の計測互換）
class TraceWriter {
  TraceWriter(this._writeLine, {int Function()? nowUs})
      : _nowUs = nowUs ?? _systemNowUs;

  static int _systemNowUs() => DateTime.now().microsecondsSinceEpoch;

  /// 現行のtraceスキーマバージョン。
  static const schemaVersion = '1';

  final void Function(String line) _writeLine;
  final int Function() _nowUs;

  int _seq = 0;
  int _nextTestId = 0;
  int _nextStepId = 0;
  final Map<int, int> _testStartedAtUs = {};
  final Map<int, int> _stepStartedAtUs = {};

  void _emit(TraceEvent Function(int seq, int timestampUs) build) {
    _writeLine(traceEventToJson(build(++_seq, _nowUs())));
  }

  void runStart({required String runId, required String platform}) {
    _emit((seq, now) => TraceEvent(
          type: TraceEventType.RUN_START,
          seq: seq,
          timestampUs: now,
          schemaVersion: schemaVersion,
          runId: runId,
          platform: platform,
        ));
  }

  /// テスト開始を記録し、採番したtestIdを返す。
  int testStart(String name) {
    final testId = ++_nextTestId;
    _emit((seq, now) {
      _testStartedAtUs[testId] = now;
      return TraceEvent(
        type: TraceEventType.TEST_START,
        seq: seq,
        timestampUs: now,
        testId: testId,
        name: name,
      );
    });
    return testId;
  }

  void testEnd(int testId, TraceStatus status, {String? error}) {
    _emit((seq, now) => TraceEvent(
          type: TraceEventType.TEST_END,
          seq: seq,
          timestampUs: now,
          testId: testId,
          status: status,
          error: error,
          durationUs: now - (_testStartedAtUs.remove(testId) ?? now),
        ));
  }

  /// ステップ開始を記録し、採番したstepIdを返す。
  int stepStart(String name, {required int testId}) {
    final stepId = ++_nextStepId;
    _emit((seq, now) {
      _stepStartedAtUs[stepId] = now;
      return TraceEvent(
        type: TraceEventType.STEP_START,
        seq: seq,
        timestampUs: now,
        testId: testId,
        stepId: stepId,
        name: name,
      );
    });
    return stepId;
  }

  void stepEnd(
    int stepId,
    TraceStatus status, {
    String? error,
    String? screenshot,
  }) {
    _emit((seq, now) => TraceEvent(
          type: TraceEventType.STEP_END,
          seq: seq,
          timestampUs: now,
          stepId: stepId,
          status: status,
          error: error,
          screenshot: screenshot,
          durationUs: now - (_stepStartedAtUs.remove(stepId) ?? now),
        ));
  }

  /// ログをステップ相関つきで記録する（stepId省略時は実行全体のログ）。
  void log(LogSource source, String message, {int? stepId}) {
    _emit((seq, now) => TraceEvent(
          type: TraceEventType.LOG,
          seq: seq,
          timestampUs: now,
          source: source,
          message: message,
          stepId: stepId,
        ));
  }

  void runEnd() {
    _emit((seq, now) => TraceEvent(
          type: TraceEventType.RUN_END,
          seq: seq,
          timestampUs: now,
        ));
  }
}
