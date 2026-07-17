import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter/widgets.dart';

import '../finder/finder.dart';
import '../interaction/pointer_synthesizer.dart';
import '../wait/frame_signal.dart';
import '../wait/frame_waiter.dart';
import '../wait/stability_tracker.dart';
import '../wait/wait_exception.dart';

/// テスト本文に渡されるテスターAPI（CORE-001〜006の中核）。
///
/// - `$`記法のファインダー、位置安定チェックつきタップ、ポーリング型expect
/// - `step()` はTraceWriterへstepStart/stepEndとして記録される（証跡の単位）
class EndevirTester {
  EndevirTester({
    required TraceWriter writer,
    required int testId,
    FrameSignal frameSignal = const SchedulerFrameSignal(),
    Element Function()? rootResolver,
    this.stabilityFrames = 3,
    this.defaultTimeout = const Duration(seconds: 10),
  })  : _writer = writer,
        _testId = testId,
        _waiter = FrameWaiter(frameSignal),
        _rootResolver = rootResolver ?? _defaultRoot;

  static Element _defaultRoot() => WidgetsBinding.instance.rootElement!;

  final TraceWriter _writer;
  final int _testId;
  final FrameWaiter _waiter;
  final Element Function() _rootResolver;
  final PointerSynthesizer _pointer = PointerSynthesizer();

  /// タップ前の位置安定判定に必要な連続不変フレーム数（CORE-103で上書き可能）。
  final int stabilityFrames;

  /// 待機のデフォルトタイムアウト（CORE-103で上書き可能）。
  final Duration defaultTimeout;

  /// 手順を命名して実行する。証跡の表示単位になる（CORE-006 / RPT-003）。
  Future<T> step<T>(String name, Future<T> Function() body) async {
    final stepId = _writer.stepStart(name, testId: _testId);
    try {
      final result = await body();
      _writer.stepEnd(stepId, TraceStatus.PASSED);
      return result;
    } catch (e) {
      _writer.stepEnd(stepId, TraceStatus.FAILED, error: '$e');
      rethrow;
    }
  }

  /// ファインダーを構築する（`e.$(#loginButton).tap()` 形式の入口）。
  // ignore: non_constant_identifier_names
  EndevirElement $(Object target) =>
      EndevirElement(EndevirFinder.from(target), this);

  /// 対象が表示されるまで待つ（アサーション=待機、CORE-005）。
  Future<WaitResult> expectVisible(Object target, {Duration? timeout}) {
    final finder = EndevirFinder.from(target);
    return _waiter.waitUntil(
      () => finder.resolve(_rootResolver()).isNotEmpty,
      timeout: timeout ?? defaultTimeout,
      describe: 'visible: ${finder.describe()}',
    );
  }
}

/// ファインダーへの操作ハンドル。
class EndevirElement {
  EndevirElement(this._finder, this._tester);

  final EndevirFinder _finder;
  final EndevirTester _tester;

  /// 対象の出現と位置安定（actionability check、ADR-003）を待ってタップする。
  Future<void> tap({Duration? timeout}) async {
    final tracker =
        StabilityTracker(requiredFrames: _tester.stabilityFrames);
    await _tester._waiter.waitUntil(
      () => tracker.update(_currentCenter()),
      timeout: timeout ?? _tester.defaultTimeout,
      describe: 'tap(stable): ${_finder.describe()}',
    );
    final center = _currentCenter();
    if (center == null) {
      throw StateError('tap target vanished: ${_finder.describe()}');
    }
    await _tester._pointer.tapAt(center);
  }

  /// 対象が表示されるまで待つ。
  Future<WaitResult> waitUntilVisible({Duration? timeout}) =>
      _tester.expectVisible(_finder, timeout: timeout);

  Offset? _currentCenter() {
    final elements = _finder.resolve(_tester._rootResolver());
    if (elements.isEmpty) return null;
    final renderObject = elements.first.renderObject;
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    return renderObject.localToGlobal(
      renderObject.size.center(Offset.zero),
    );
  }
}
