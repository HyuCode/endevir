import 'package:endevir_reporter/endevir_reporter.dart';

/// ログのステップ相関（RPT-002/405）。
///
/// 実行中のステップIDをスタックで追跡し、捕捉したログを
/// 「現在のステップ」に紐付けてtraceへ記録する。
/// - ステップの出入りは[EndevirTester.step]がpush/popする
/// - ログの捕捉はランナーの実行ゾーン（printハンドラ）が[emit]を呼ぶ
class LogCorrelator {
  TraceWriter? _writer;
  final List<int> _stepStack = [];

  /// 実行開始時にライターを紐付ける（実行外のemitは無視される）。
  void attach(TraceWriter writer) => _writer = writer;

  void detach() {
    _writer = null;
    _stepStack.clear();
  }

  /// 現在実行中のステップID（ステップ外ならnull）。
  int? get currentStepId => _stepStack.isEmpty ? null : _stepStack.last;

  void pushStep(int stepId) => _stepStack.add(stepId);

  void popStep() {
    if (_stepStack.isNotEmpty) _stepStack.removeLast();
  }

  /// 捕捉したログを現在のステップに相関させて記録する。
  void emit(String message, {LogSource source = LogSource.DART}) {
    _writer?.log(source, message, stepId: currentStepId);
  }
}
