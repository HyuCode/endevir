import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoSwitch;
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart'
    show
        ButtonStyleButton,
        Checkbox,
        FloatingActionButton,
        IconButton,
        Slider,
        Switch,
        TextField;
import 'package:flutter/widgets.dart';

import '../evidence/evidence_recorder.dart';
import '../finder/finder.dart';
import '../interaction/pointer_synthesizer.dart';
import '../runner/log_correlator.dart';
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
    EvidenceRecorder? evidence,
    this.screenshotMode = ScreenshotMode.onFailure,
    this.attempt = 1,
    LogCorrelator? logCorrelator,
  }) : _writer = writer,
       _testId = testId,
       _waiter = FrameWaiter(frameSignal),
       _rootResolver = rootResolver ?? _defaultRoot,
       _evidence = evidence,
       _logCorrelator = logCorrelator;

  static Element _defaultRoot() => WidgetsBinding.instance.rootElement!;

  final TraceWriter _writer;
  final int _testId;
  final FrameWaiter _waiter;
  final Element Function() _rootResolver;
  final PointerSynthesizer _pointer = PointerSynthesizer();
  final EvidenceRecorder? _evidence;
  final LogCorrelator? _logCorrelator;

  /// スクリーンショットの記録プリセット（RPT-004）。
  final ScreenshotMode screenshotMode;

  /// このテストの試行番号（onFirstRetryモードの判定に使う）。
  final int attempt;

  /// タップ前の位置安定判定に必要な連続不変フレーム数（CORE-103で上書き可能）。
  final int stabilityFrames;

  /// 待機のデフォルトタイムアウト（CORE-103で上書き可能）。
  final Duration defaultTimeout;

  /// 手順を命名して実行する。証跡の表示単位になる（CORE-006 / RPT-003）。
  ///
  /// スクリーンショットは[screenshotMode]に従い、ステップ完了時点の画面を
  /// 記録する（GPUスナップショットのみ同期、エンコードは遅延。ADR-004）。
  Future<T> step<T>(String name, Future<T> Function() body) async {
    final stepId = _writer.stepStart(name, testId: _testId);
    _logCorrelator?.pushStep(stepId);
    try {
      final result = await body();
      _writer.stepEnd(
        stepId,
        TraceStatus.PASSED,
        screenshot: await _captureIf(passed: true, stepId: stepId),
      );
      return result;
    } catch (e) {
      _writer.stepEnd(
        stepId,
        TraceStatus.FAILED,
        error: '$e',
        screenshot: await _captureIf(passed: false, stepId: stepId),
      );
      rethrow;
    } finally {
      _logCorrelator?.popStep();
    }
  }

  Future<String?> _captureIf({
    required bool passed,
    required int stepId,
  }) async {
    final recorder = _evidence;
    if (recorder == null) return null;
    final shouldCapture = switch (screenshotMode) {
      ScreenshotMode.evidence => true,
      ScreenshotMode.onFailure => !passed,
      ScreenshotMode.onFirstRetry => attempt > 1,
      ScreenshotMode.none => false,
    };
    if (!shouldCapture) return null;
    try {
      return await recorder.captureForStep(stepId);
    } catch (e) {
      _writer.log(LogSource.RUNNER, 'screenshot failed: $e', stepId: stepId);
      return null;
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
      () => _resolveSingleVisible(finder) != null,
      timeout: timeout ?? defaultTimeout,
      describe: 'visible: ${finder.describe()}',
    );
  }

  List<Element> _resolveVisible(EndevirFinder finder) => finder
      .resolve(_rootResolver())
      .where(_isActuallyVisible)
      .toList(growable: false);

  Element? _resolveSingleVisible(EndevirFinder finder) {
    final elements = _resolveVisible(finder);
    if (elements.length > 1) {
      throw AmbiguousFinderException(
        finder.describe(),
        elements.map(_describeCandidate).toList(growable: false),
      );
    }
    return elements.firstOrNull;
  }

  String _describeCandidate(Element element) {
    final widget = element.widget;
    final key = widget.key;
    final text = widget is Text ? widget.data : null;
    final renderObject = element.renderObject;
    final rect =
        renderObject is RenderBox &&
            renderObject.attached &&
            renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
    return '- ${widget.runtimeType}'
        '${key == null ? '' : ' key=$key'}'
        '${text == null ? '' : ' text="$text"'}'
        '${rect == null ? '' : ' rect=$rect'}';
  }

  bool _isActuallyVisible(Element element) {
    var hiddenByAncestor = false;
    bool isHidden(Widget widget) =>
        (widget is Offstage && widget.offstage) ||
        (widget is Visibility && !widget.visible) ||
        (widget is Opacity && widget.opacity == 0) ||
        (widget is AnimatedOpacity && widget.opacity == 0) ||
        (widget is FadeTransition && widget.opacity.value == 0);

    if (isHidden(element.widget)) return false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (isHidden(widget)) {
        hiddenByAncestor = true;
        return false;
      }
      return true;
    });
    if (hiddenByAncestor) return false;

    final renderObject = element.renderObject;
    if (renderObject is RenderBox) {
      if (!renderObject.attached ||
          !renderObject.hasSize ||
          renderObject.size.isEmpty) {
        return false;
      }
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view == null) return false;
      final viewport =
          Offset.zero & (view.physicalSize / view.devicePixelRatio);
      final center = renderObject.localToGlobal(
        renderObject.size.center(Offset.zero),
      );
      return viewport.contains(center);
    }
    return renderObject?.attached ?? false;
  }

  bool _isPointerActionable(Element element, Offset center) {
    if (!_isEnabledForPointerAction(element)) return false;

    final targetRenderObjects = <RenderObject>{};
    void collectRenderObjects(Element current) {
      final renderObject = current.renderObject;
      if (renderObject != null) targetRenderObjects.add(renderObject);
      current.visitChildren(collectRenderObjects);
    }

    collectRenderObjects(element);
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (targetRenderObjects.isEmpty || view == null) return false;

    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, center, view.viewId);
    return result.path.any((entry) {
      final target = entry.target;
      if (target is! RenderObject) return false;
      RenderObject? current = target;
      while (current != null) {
        if (targetRenderObjects.contains(current)) return true;
        final parent = current.parent;
        current = parent is RenderObject ? parent : null;
      }
      return false;
    });
  }

  bool _isEnabledForPointerAction(Element element) {
    var enabled = true;

    bool widgetIsEnabled(Widget widget) {
      if (widget is IgnorePointer && widget.ignoring) return false;
      if (widget is AbsorbPointer && widget.absorbing) return false;
      if (widget is Semantics && widget.properties.enabled == false) {
        return false;
      }
      if (widget is ButtonStyleButton) return widget.enabled;
      if (widget is IconButton) return widget.onPressed != null;
      if (widget is FloatingActionButton) return widget.onPressed != null;
      if (widget is Switch) return widget.onChanged != null;
      if (widget is Checkbox) return widget.onChanged != null;
      if (widget is Slider) return widget.onChanged != null;
      if (widget is TextField) return widget.enabled != false;
      if (widget is CupertinoButton) return widget.onPressed != null;
      if (widget is CupertinoSwitch) return widget.onChanged != null;
      return true;
    }

    if (!widgetIsEnabled(element.widget)) return false;
    element.visitAncestorElements((ancestor) {
      if (!widgetIsEnabled(ancestor.widget)) {
        enabled = false;
        return false;
      }
      return true;
    });
    return enabled;
  }
}

/// ファインダーへの操作ハンドル。
class EndevirElement {
  EndevirElement(this._finder, this._tester);

  final EndevirFinder _finder;
  final EndevirTester _tester;

  /// 対象の出現と位置安定（actionability check、ADR-003）を待ってタップする。
  Future<void> tap({Duration? timeout}) async {
    final tracker = StabilityTracker(requiredFrames: _tester.stabilityFrames);
    await _tester._waiter.waitUntil(
      () => tracker.update(_currentActionableCenter()),
      timeout: timeout ?? _tester.defaultTimeout,
      describe: 'tap(stable): ${_finder.describe()}',
      // 安定判定は連続フレームでの評価が前提（静止画面ではフレームが
      // 流れないため、評価ごとに次フレームを要求する）
      keepFramesFlowing: true,
    );
    final center = _currentActionableCenter();
    if (center == null) {
      throw StateError('tap target vanished: ${_finder.describe()}');
    }
    await _tester._pointer.tapAt(center);
  }

  /// 対象の中心から[delta]分だけドラッグする。
  Future<void> dragBy(Offset delta, {Duration? timeout}) async {
    final tracker = StabilityTracker(requiredFrames: _tester.stabilityFrames);
    await _tester._waiter.waitUntil(
      () => tracker.update(_currentActionableCenter()),
      timeout: timeout ?? _tester.defaultTimeout,
      describe: 'drag(stable): ${_finder.describe()}',
      keepFramesFlowing: true,
    );
    final center = _currentActionableCenter();
    if (center == null) {
      throw StateError('drag target vanished: ${_finder.describe()}');
    }
    await _tester._pointer.dragBy(center, delta);
  }

  /// 対象が表示されるまで待つ。
  Future<WaitResult> waitUntilVisible({Duration? timeout}) =>
      _tester.expectVisible(_finder, timeout: timeout);

  /// このスコープの配下から検索するハンドルを返す（チェーン、CORE-002）。
  // ignore: non_constant_identifier_names
  EndevirElement $(Object target) => EndevirElement(
    EndevirFinder.descendant(of: _finder, matching: EndevirFinder.from(target)),
    _tester,
  );

  /// 対象（またはその配下のEditableText）へテキストを入力する。
  ///
  /// フォーカスを与えてIME経由相当の編集値更新を行う。本番モードで動作する
  /// （WidgetTester非依存）。
  Future<void> enterText(String text, {Duration? timeout}) async {
    final tracker = StabilityTracker(requiredFrames: _tester.stabilityFrames);
    await _tester._waiter.waitUntil(
      () => tracker.update(_currentActionableCenter(forTextInput: true)),
      timeout: timeout ?? _tester.defaultTimeout,
      describe: 'enterText(stable): ${_finder.describe()}',
      keepFramesFlowing: true,
    );

    final element = _tester._resolveSingleVisible(_finder);
    if (element == null) {
      throw StateError('入力対象が表示されていません: ${_finder.describe()}');
    }
    final editable = _findEditableText(element);
    if (editable == null) {
      throw StateError('EditableTextが見つかりません: ${_finder.describe()}');
    }
    if (editable.widget.readOnly ||
        !editable.widget.focusNode.canRequestFocus) {
      throw StateError('入力対象が無効です: ${_finder.describe()}');
    }
    editable.widget.focusNode.requestFocus();
    editable.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  /// 要素自身または配下からEditableTextStateを探す。
  EditableTextState? _findEditableText(Element element) {
    EditableTextState? found;
    void visit(Element el) {
      if (found != null) return;
      if (el is StatefulElement && el.state is EditableTextState) {
        found = el.state as EditableTextState;
        return;
      }
      el.visitChildren(visit);
    }

    visit(element);
    return found;
  }

  Offset? _currentActionableCenter({bool forTextInput = false}) {
    final element = _tester._resolveSingleVisible(_finder);
    if (element == null) return null;
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    final center = renderObject.localToGlobal(
      renderObject.size.center(Offset.zero),
    );
    if (!_tester._isPointerActionable(element, center)) return null;
    if (forTextInput) {
      final editable = _findEditableText(element);
      if (editable == null ||
          editable.widget.readOnly ||
          !editable.widget.focusNode.canRequestFocus) {
        return null;
      }
    }
    return center;
  }
}
