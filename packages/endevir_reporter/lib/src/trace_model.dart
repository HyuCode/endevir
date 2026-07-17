import 'generated/trace_event.g.dart';

/// traceイベント列を構造化したモデル（ビューア・レポートの共通入力）。
class TraceModel {
  TraceModel._({
    required this.runId,
    required this.platform,
    required this.tests,
  });

  /// イベント列（seq順）からモデルを構築する。
  factory TraceModel.fromEvents(List<TraceEvent> events) {
    String runId = '';
    String platform = '';
    final tests = <TestModel>[];
    final testsById = <int, TestModel>{};
    final stepsById = <int, StepModel>{};
    final stepTestById = <int, int>{};

    for (final event in events) {
      switch (event.type) {
        case TraceEventType.RUN_START:
          runId = event.runId ?? '';
          platform = event.platform ?? '';
        case TraceEventType.TEST_START:
          final test = TestModel(id: event.testId!, name: event.name ?? '');
          tests.add(test);
          testsById[test.id] = test;
        case TraceEventType.TEST_END:
          final test = testsById[event.testId];
          test
            ?..status = event.status
            ..error = event.error
            ..durationUs = event.durationUs;
        case TraceEventType.STEP_START:
          final step = StepModel(id: event.stepId!, name: event.name ?? '');
          stepsById[step.id] = step;
          stepTestById[step.id] = event.testId!;
          testsById[event.testId]?.steps.add(step);
        case TraceEventType.STEP_END:
          final step = stepsById[event.stepId];
          step
            ?..status = event.status
            ..error = event.error
            ..screenshot = event.screenshot
            ..durationUs = event.durationUs;
        case TraceEventType.LOG:
          final log = LogModel(
            source: event.source,
            message: event.message ?? '',
            timestampUs: event.timestampUs,
          );
          final step = stepsById[event.stepId];
          if (step != null) {
            step.logs.add(log);
          }
        case TraceEventType.RUN_END:
          break;
      }
    }

    return TraceModel._(runId: runId, platform: platform, tests: tests);
  }

  final String runId;
  final String platform;
  final List<TestModel> tests;

  int get total => tests.length;
  int get passed =>
      tests.where((t) => t.status == TraceStatus.PASSED).length;
  int get failed =>
      tests.where((t) => t.status == TraceStatus.FAILED).length;
}

class TestModel {
  TestModel({required this.id, required this.name});

  final int id;
  final String name;
  TraceStatus? status;
  String? error;
  int? durationUs;
  final List<StepModel> steps = [];
}

class StepModel {
  StepModel({required this.id, required this.name});

  final int id;
  final String name;
  TraceStatus? status;
  String? error;
  String? screenshot;
  int? durationUs;
  final List<LogModel> logs = [];
}

class LogModel {
  LogModel({
    required this.source,
    required this.message,
    required this.timestampUs,
  });

  final LogSource? source;
  final String message;
  final int timestampUs;
}
