import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoSwitch;
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/material.dart'
    show
        ButtonStyleButton,
        Checkbox,
        FloatingActionButton,
        IconButton,
        Slider,
        Switch,
        SwitchListTile,
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
    this.settleFrames = 1,
    this.defaultTimeout = const Duration(seconds: 10),
    EvidenceRecorder? evidence,
    this.screenshotMode = ScreenshotMode.onFailure,
    this.attempt = 1,
    LogCorrelator? logCorrelator,
  }) : _writer = writer,
       assert(stabilityFrames > 0),
       assert(settleFrames >= 0),
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

  /// action完了後に待つ最小フレーム数。全画面の静止は待たない。
  final int settleFrames;

  /// 待機のデフォルトタイムアウト（CORE-103で上書き可能）。
  final Duration defaultTimeout;

  /// UIの状態更新が反映されるまで、指定数のフレーム終端を待つ。
  Future<WaitResult> settle({int? frames, Duration? timeout}) =>
      _waiter.waitForFrames(
        frames ?? settleFrames,
        timeout: timeout ?? defaultTimeout,
      );

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

  /// 対象が表示されなくなるまで待つ。
  ///
  /// 対象がElementツリーから消えた場合と、Offstage等で実際に見えなくなった場合の
  /// どちらも成功とする。
  Future<WaitResult> expectNotVisible(Object target, {Duration? timeout}) {
    final finder = EndevirFinder.from(target);
    return _waiter.waitUntil(
      () => _resolveVisible(finder).isEmpty,
      timeout: timeout ?? defaultTimeout,
      describe: 'not visible: ${finder.describe()}',
    );
  }

  List<Element> _resolveVisible(EndevirFinder finder) => finder
      .resolve(_rootResolver())
      .where(_isActuallyVisible)
      .toList(growable: false);

  List<Element> _resolveMounted(EndevirFinder finder) => finder
      .resolve(_rootResolver())
      .where(_isMountedAndTreeVisible)
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

  Element? _resolveSingleMounted(EndevirFinder finder) {
    final elements = _resolveMounted(finder);
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
    return '- path=${_elementPath(element)}'
        '${key == null ? '' : ' key=$key'}'
        '${text == null ? '' : ' text="$text"'}'
        '${rect == null ? '' : ' rect=$rect'}';
  }

  String _elementPath(Element element) {
    final segments = <String>[_elementSegment(element)];
    element.visitAncestorElements((ancestor) {
      segments.add(_elementSegment(ancestor));
      return segments.length < 8;
    });
    return segments.reversed.join(' > ');
  }

  String _elementSegment(Element element) {
    final key = element.widget.key;
    return '${element.widget.runtimeType}${key == null ? '' : '[$key]'}';
  }

  bool _isActuallyVisible(Element element) {
    return _visibilityFailure(element) == null;
  }

  String? _visibilityFailure(Element element) {
    String? hiddenReason(Widget widget) => switch (widget) {
      final Offstage widget when widget.offstage => 'Offstage(offstage: true)',
      final Visibility widget when !widget.visible =>
        'Visibility(visible: false)',
      final Opacity widget when widget.opacity == 0 => 'Opacity(opacity: 0)',
      final AnimatedOpacity widget when widget.opacity == 0 =>
        'AnimatedOpacity(opacity: 0)',
      final FadeTransition widget when widget.opacity.value == 0 =>
        'FadeTransition(opacity: 0)',
      _ => null,
    };

    final ownReason = hiddenReason(element.widget);
    if (ownReason != null) return 'hidden by $ownReason';
    String? ancestorReason;
    element.visitAncestorElements((ancestor) {
      final reason = hiddenReason(ancestor.widget);
      if (reason != null) {
        ancestorReason =
            'hidden by ancestor ${ancestor.widget.runtimeType}: $reason';
        return false;
      }
      return true;
    });
    if (ancestorReason != null) return ancestorReason;

    final renderObject = element.renderObject;
    if (renderObject is RenderBox) {
      if (!renderObject.attached) return 'render object is detached';
      if (!renderObject.hasSize || renderObject.size.isEmpty) {
        return 'render box has no non-empty size';
      }
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view == null) return 'no implicit Flutter view is available';
      final viewport =
          Offset.zero & (view.physicalSize / view.devicePixelRatio);
      final center = renderObject.localToGlobal(
        renderObject.size.center(Offset.zero),
      );
      if (!viewport.contains(center)) {
        return 'center $center is outside viewport $viewport';
      }
      return null;
    }
    if (renderObject == null || !renderObject.attached) {
      return 'render object is missing or detached';
    }
    return null;
  }

  bool _isMountedAndTreeVisible(Element element) {
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
      return true;
    }
    return renderObject?.attached ?? false;
  }

  String? _pointerActionabilityFailure(Element element, Offset center) {
    if (!_isEnabledForPointerAction(element)) {
      return 'target or ancestor is disabled or ignores pointer events';
    }

    final targetRenderObjects = <RenderObject>{};
    void collectRenderObjects(Element current) {
      final renderObject = current.renderObject;
      if (renderObject != null) targetRenderObjects.add(renderObject);
      current.visitChildren(collectRenderObjects);
    }

    collectRenderObjects(element);
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (targetRenderObjects.isEmpty) return 'target has no render objects';
    if (view == null) return 'no implicit Flutter view is available';

    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, center, view.viewId);
    final hit = result.path.any((entry) {
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
    return hit
        ? null
        : 'center $center is clipped, blocked by another element, or not hit-testable';
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
  String _lastActionabilityReason = 'target was not evaluated';
  List<String> _lastCandidates = const [];

  /// 対象の出現と位置安定（actionability check、ADR-003）を待ってタップする。
  Future<void> tap({Duration? timeout}) async {
    final tracker = StabilityTracker(requiredFrames: _tester.stabilityFrames);
    await _waitForStableAction('tap', tracker, timeout: timeout);
    final center = _currentActionableCenter();
    if (center == null) {
      throw StateError('tap target vanished: ${_finder.describe()}');
    }
    await _tester._pointer.tapAt(center);
    await _tester.settle(timeout: timeout);
  }

  /// 対象の中心を長押しする。
  Future<void> longPress({
    Duration duration = const Duration(milliseconds: 600),
    Duration? timeout,
  }) async {
    final center = await _stableCenter('longPress', timeout: timeout);
    await _tester._pointer.longPressAt(center, duration: duration);
    await _tester.settle(timeout: timeout);
  }

  /// 対象の中心から[delta]分だけドラッグする。
  Future<void> dragBy(Offset delta, {Duration? timeout}) async {
    final tracker = StabilityTracker(requiredFrames: _tester.stabilityFrames);
    await _waitForStableAction('drag', tracker, timeout: timeout);
    final center = _currentActionableCenter();
    if (center == null) {
      throw StateError('drag target vanished: ${_finder.describe()}');
    }
    await _tester._pointer.dragBy(center, delta);
    await _tester.settle(timeout: timeout);
  }

  /// 対象の中心から[delta]方向へスワイプする。
  Future<void> swipe(
    Offset delta, {
    Duration duration = const Duration(milliseconds: 250),
    Duration? timeout,
  }) async {
    final center = await _stableCenter('swipe', timeout: timeout);
    await _tester._pointer.swipeBy(center, delta, duration: duration);
    await _tester.settle(timeout: timeout);
  }

  /// 対象の中心から[delta]方向へ指定速度でフリングする。
  Future<void> fling(
    Offset delta, {
    double velocity = 1500,
    Duration? timeout,
  }) async {
    final center = await _stableCenter('fling', timeout: timeout);
    await _tester._pointer.flingBy(center, delta, velocity: velocity);
    await _tester.settle(timeout: timeout);
  }

  Future<Offset> _stableCenter(String action, {Duration? timeout}) async {
    final tracker = StabilityTracker(requiredFrames: _tester.stabilityFrames);
    await _waitForStableAction(action, tracker, timeout: timeout);
    final center = _currentActionableCenter();
    if (center == null) {
      throw StateError('$action target vanished: ${_finder.describe()}');
    }
    return center;
  }

  /// 対象が表示されるまで待つ。
  Future<WaitResult> waitUntilVisible({Duration? timeout}) =>
      _tester.expectVisible(_finder, timeout: timeout);

  /// 対象がアクセシビリティ上の選択状態になるまで待つ。
  ///
  /// SegmentedButtonやTab等、利用者に表示される選択状態の検証に使う。
  Future<WaitResult> expectSelected({bool value = true, Duration? timeout}) =>
      _waitForBooleanState(
        stateName: 'selected',
        expected: value,
        readSemantics: (properties) => properties.selected,
        timeout: timeout,
      );

  /// 対象がアクセシビリティ上のon/off状態になるまで待つ。
  ///
  /// Switch系の公開UI状態を検証する。SwitchListTileは同等の公開valueへ
  /// フォールバックし、将来の外部ドライバーではsemanticsへ写像できる契約とする。
  Future<WaitResult> expectToggled(bool value, {Duration? timeout}) =>
      _waitForBooleanState(
        stateName: 'toggled',
        expected: value,
        readSemantics: (properties) => properties.toggled,
        readWidget: (widget) => switch (widget) {
          final Switch widget => widget.value,
          final SwitchListTile widget => widget.value,
          final CupertinoSwitch widget => widget.value,
          _ => null,
        },
        timeout: timeout,
      );

  Future<WaitResult> _waitForBooleanState({
    required String stateName,
    required bool expected,
    required bool? Function(SemanticsProperties properties) readSemantics,
    bool? Function(Widget widget)? readWidget,
    Duration? timeout,
  }) => _tester._waiter.waitUntil(
    () {
      final element = _tester._resolveSingleVisible(_finder);
      if (element == null) return false;
      return _readBooleanState(element, readSemantics, readWidget) == expected;
    },
    timeout: timeout ?? _tester.defaultTimeout,
    describe: '$stateName=$expected: ${_finder.describe()}',
  );

  bool? _readBooleanState(
    Element element,
    bool? Function(SemanticsProperties properties) readSemantics,
    bool? Function(Widget widget)? readWidget,
  ) {
    bool? read(Element candidate) {
      final widgetValue = readWidget?.call(candidate.widget);
      if (widgetValue != null) return widgetValue;
      final widget = candidate.widget;
      return widget is Semantics ? readSemantics(widget.properties) : null;
    }

    final ownValue = read(element);
    if (ownValue != null) return ownValue;

    bool? ancestorValue;
    element.visitAncestorElements((ancestor) {
      ancestorValue = read(ancestor);
      return ancestorValue == null;
    });
    if (ancestorValue != null) return ancestorValue;

    bool? descendantValue;
    void visit(Element descendant) {
      if (descendantValue != null) return;
      descendantValue = read(descendant);
      if (descendantValue == null) descendant.visitChildren(visit);
    }

    element.visitChildren(visit);
    return descendantValue;
  }

  /// 最も近いScrollableを使って対象をviewport内へ移動する。
  Future<void> ensureVisible({
    Duration duration = const Duration(milliseconds: 200),
    double alignment = 0,
    Duration? timeout,
  }) async {
    Element? element;
    await _tester._waiter.waitUntil(
      () {
        element = _tester._resolveSingleMounted(_finder);
        return element != null;
      },
      timeout: timeout ?? _tester.defaultTimeout,
      describe: 'mounted: ${_finder.describe()}',
    );
    await Scrollable.ensureVisible(
      element!,
      duration: duration,
      alignment: alignment,
    );
    await waitUntilVisible(timeout: timeout);
  }

  /// 対象が表示されるまで指定Scrollableを段階的にドラッグする。
  ///
  /// 遅延構築されるListViewのように、対象がまだElementツリーに存在しない
  /// 場合にも利用できる。
  Future<void> scrollUntilVisible({
    required Object scrollable,
    Offset delta = const Offset(0, -300),
    int maxScrolls = 20,
    Duration? timeout,
  }) async {
    if (maxScrolls <= 0) {
      throw ArgumentError.value(maxScrolls, 'maxScrolls', '1以上を指定してください');
    }
    final effectiveTimeout = timeout ?? _tester.defaultTimeout;
    for (var attempt = 0; attempt <= maxScrolls; attempt++) {
      if (_tester._resolveSingleVisible(_finder) != null) return;
      if (_tester._resolveSingleMounted(_finder) != null) {
        await ensureVisible(timeout: effectiveTimeout);
        return;
      }
      if (attempt < maxScrolls) {
        await _tester.$(scrollable).dragBy(delta, timeout: effectiveTimeout);
      }
    }
    throw WaitTimeoutException(
      'scroll failed: ${_finder.describe()}',
      effectiveTimeout,
      evaluations: maxScrolls + 1,
    );
  }

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
    await _waitForStableAction(
      'enterText',
      tracker,
      timeout: timeout,
      forTextInput: true,
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
    await _tester.settle(timeout: timeout);
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
    final matches = _finder.resolve(_tester._rootResolver());
    _lastCandidates = matches
        .map(_tester._describeCandidate)
        .toList(growable: false);
    if (matches.isEmpty) {
      _lastActionabilityReason = 'no elements matched the finder';
      return null;
    }
    final visible = matches
        .where((element) => _tester._visibilityFailure(element) == null)
        .toList(growable: false);
    if (visible.length > 1) {
      throw AmbiguousFinderException(
        _finder.describe(),
        visible.map(_tester._describeCandidate).toList(growable: false),
      );
    }
    if (visible.isEmpty) {
      _lastCandidates = matches
          .map(
            (element) =>
                '${_tester._describeCandidate(element)} '
                'reason=${_tester._visibilityFailure(element)}',
          )
          .toList(growable: false);
      _lastActionabilityReason = 'all matched elements are not visible';
      return null;
    }
    final element = visible.single;
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.attached) {
      _lastActionabilityReason = 'target has no attached RenderBox';
      return null;
    }
    final center = renderObject.localToGlobal(
      renderObject.size.center(Offset.zero),
    );
    final pointerFailure = _tester._pointerActionabilityFailure(
      element,
      center,
    );
    if (pointerFailure != null) {
      _lastActionabilityReason = pointerFailure;
      return null;
    }
    if (forTextInput) {
      final editable = _findEditableText(element);
      if (editable == null) {
        _lastActionabilityReason = 'target has no EditableText descendant';
        return null;
      }
      if (editable.widget.readOnly) {
        _lastActionabilityReason = 'EditableText is read-only';
        return null;
      }
      if (!editable.widget.focusNode.canRequestFocus) {
        _lastActionabilityReason = 'EditableText cannot request focus';
        return null;
      }
    }
    _lastActionabilityReason =
        'position did not remain stable for ${_tester.stabilityFrames} frames';
    return center;
  }

  Future<void> _waitForStableAction(
    String action,
    StabilityTracker tracker, {
    Duration? timeout,
    bool forTextInput = false,
  }) async {
    final effectiveTimeout = timeout ?? _tester.defaultTimeout;
    try {
      await _tester._waiter.waitUntil(
        () => tracker.update(
          _currentActionableCenter(forTextInput: forTextInput),
        ),
        timeout: effectiveTimeout,
        describe: '$action(stable): ${_finder.describe()}',
        // 安定判定は連続フレームでの評価が前提（静止画面ではフレームが
        // 流れないため、評価ごとに次フレームを要求する）
        keepFramesFlowing: true,
      );
    } on WaitTimeoutException catch (error) {
      throw ActionabilityTimeoutException(
        action: action,
        finder: _finder.describe(),
        reason: _lastActionabilityReason,
        candidates: _lastCandidates,
        duration: effectiveTimeout,
        evaluations: error.evaluations,
      );
    }
  }
}
