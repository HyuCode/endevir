import 'package:endevir/src/evidence/evidence_recorder.dart';
import 'package:endevir/src/finder/finder.dart';
import 'package:endevir/src/tester/endevir_tester.dart';
import 'package:endevir/src/wait/wait_exception.dart';
import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../evidence/evidence_recorder_test.dart' show FakeCapturer;
import '../wait/frame_waiter_test.dart' show ManualFrameSignal;

void main() {
  group('スクリーンショット統合', _screenshotTests);

  late List<String> lines;
  late TraceWriter writer;
  late ManualFrameSignal signal;

  setUp(() {
    lines = [];
    writer = TraceWriter(lines.add, nowUs: () => 0);
    signal = ManualFrameSignal();
  });

  EndevirTester makeTester(WidgetTester tester) => EndevirTester(
    writer: writer,
    testId: 1,
    frameSignal: signal,
    rootResolver: () => tester.binding.rootElement!,
  );

  Widget counterApp() => const MaterialApp(home: _CounterScreen());

  testWidgets('expectVisibleは対象が既に表示されていれば即完了する', (tester) async {
    await tester.pumpWidget(counterApp());
    final e = makeTester(tester);

    final result = await e.expectVisible('カウント: 0');

    expect(result.evaluations, 1);
  });

  testWidgets('expectVisibleは後から現れる要素をフレーム再評価で検知する', (tester) async {
    await tester.pumpWidget(counterApp());
    final e = makeTester(tester);

    var done = false;
    e.expectVisible('カウント: 1').then((_) => done = true);
    await tester.pump();
    expect(done, isFalse);

    await tester.tap(find.byKey(const ValueKey('increment')));
    await tester.pump();
    signal.tick();
    await tester.pump();

    expect(done, isTrue);
  });

  testWidgets('expectVisibleはOffstageの古い画面を表示中と判定しない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            Offstage(offstage: true, child: Text('古い画面')),
            Text('現在の画面'),
          ],
        ),
      ),
    );
    final e = makeTester(tester);

    await expectLater(e.expectVisible('現在の画面'), completes);

    final expectation = expectLater(
      e.expectVisible('古い画面', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<WaitTimeoutException>()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectation;
  });

  testWidgets('expectVisibleは画面外の要素を表示中と判定しない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(top: 1000, child: Text('画面外')),
            Text('画面内'),
          ],
        ),
      ),
    );
    final e = makeTester(tester);

    await expectLater(e.expectVisible('画面内'), completes);
    final expectation = expectLater(
      e.expectVisible('画面外', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<WaitTimeoutException>()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectation;
  });

  testWidgets('ensureVisibleはScrollable内の画面外要素を表示領域へ移動する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: Column(
            children: [
              for (var index = 0; index < 20; index++)
                SizedBox(
                  key: ValueKey('item_$index'),
                  height: 100,
                  child: Text('項目$index'),
                ),
            ],
          ),
        ),
      ),
    );
    final e = makeTester(tester);
    var done = false;

    e
        .$(const ValueKey('item_19'))
        .ensureVisible(duration: Duration.zero)
        .then((_) => done = true);
    await tester.pump();
    signal.tick();
    await tester.pump();

    expect(done, isTrue);
    expect(find.byKey(const ValueKey('item_19')), findsOneWidget);
  });

  testWidgets('scrollUntilVisibleは遅延構築ListViewの対象まで段階的にスクロールする', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          key: const ValueKey('lazy_list'),
          itemCount: 30,
          itemExtent: 100,
          itemBuilder: (context, index) => SizedBox(
            key: ValueKey('lazy_item_$index'),
            child: Text('遅延項目$index'),
          ),
        ),
      ),
    );
    final e = EndevirTester(
      writer: writer,
      testId: 1,
      rootResolver: () => tester.binding.rootElement!,
    );

    final scrolling = e
        .$(const ValueKey('lazy_item_29'))
        .scrollUntilVisible(
          scrollable: const ValueKey('lazy_list'),
          delta: const Offset(0, -500),
          maxScrolls: 10,
        );
    await tester.pumpAndSettle();
    await scrolling;

    expect(find.byKey(const ValueKey('lazy_item_29')), findsOneWidget);
  });

  testWidgets('完全一致する表示要素が複数ある場合は候補つきで失敗する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            Text('重複', key: ValueKey('first')),
            Text('重複', key: ValueKey('second')),
          ],
        ),
      ),
    );
    final e = makeTester(tester);

    expect(
      () => e.expectVisible('重複'),
      throwsA(
        isA<AmbiguousFinderException>()
            .having((error) => error.candidates, 'candidates', hasLength(2))
            .having((error) => '$error', 'message', contains('first'))
            .having((error) => '$error', 'message', contains('second')),
      ),
    );
  });

  testWidgets(r'$(...).tap()は位置安定を待ってからタップする', (tester) async {
    await tester.pumpWidget(counterApp());
    final e = makeTester(tester);

    var tapped = false;
    e.$(#increment).tap().then((_) => tapped = true);

    // 3フレーム安定するまではタップされない
    for (var i = 0; i < 4; i++) {
      signal.tick();
      await tester.pump();
    }
    expect(tapped, isTrue);
    await tester.pump();
    expect(find.text('カウント: 1'), findsOneWidget);
  });

  testWidgets('clip領域外の対象はtapしない', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: 150,
                  child: GestureDetector(
                    key: const ValueKey('clipped'),
                    onTap: () => tapped = true,
                    child: const SizedBox(width: 40, height: 40),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final e = makeTester(tester);

    final expectation = expectLater(
      e.$(#clipped).tap(timeout: const Duration(milliseconds: 50)),
      throwsA(
        isA<ActionabilityTimeoutException>().having(
          (error) => error.reason,
          'reason',
          contains('clipped, blocked by another element'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectation;
    expect(tapped, isFalse);
  });

  testWidgets('overlayに遮蔽された対象はtapしない', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            GestureDetector(
              key: const ValueKey('covered'),
              onTap: () => tapped = true,
              child: const SizedBox(width: 100, height: 100),
            ),
            const AbsorbPointer(child: SizedBox(width: 100, height: 100)),
          ],
        ),
      ),
    );
    final e = makeTester(tester);

    final expectation = expectLater(
      e.$(#covered).tap(timeout: const Duration(milliseconds: 50)),
      throwsA(
        isA<ActionabilityTimeoutException>().having(
          (error) => error.reason,
          'reason',
          contains('blocked by another element'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectation;
    expect(tapped, isFalse);
  });

  testWidgets('disabledなボタンはtapしない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ElevatedButton(
          key: ValueKey('disabled'),
          onPressed: null,
          child: Text('無効'),
        ),
      ),
    );
    final e = makeTester(tester);

    final expectation = expectLater(
      e.$(#disabled).tap(timeout: const Duration(milliseconds: 50)),
      throwsA(
        isA<ActionabilityTimeoutException>()
            .having(
              (error) => error.reason,
              'reason',
              contains('disabled or ignores pointer events'),
            )
            .having(
              (error) => error.candidates.single,
              'candidate',
              allOf(contains('path='), contains('disabled'), contains('rect=')),
            ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectation;
  });

  testWidgets('StatefulWidget配下の実ヒット対象をactionableと判定する', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DropdownButton<String>(
            key: const ValueKey('dropdown'),
            value: 'ja',
            items: const [
              DropdownMenuItem(value: 'ja', child: Text('日本語')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    final e = makeTester(tester);

    var done = false;
    e.$(#dropdown).tap().then((_) => done = true);
    for (var i = 0; i < 5 && !done; i++) {
      signal.tick();
      await tester.pump();
    }

    expect(done, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('Opacityが0の対象はtapしない', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Opacity(
          opacity: 0,
          child: GestureDetector(
            key: const ValueKey('transparent'),
            onTap: () => tapped = true,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    final e = makeTester(tester);

    final expectation = expectLater(
      e.$(#transparent).tap(timeout: const Duration(milliseconds: 50)),
      throwsA(
        isA<ActionabilityTimeoutException>()
            .having(
              (error) => error.reason,
              'reason',
              'all matched elements are not visible',
            )
            .having(
              (error) => error.candidates.single,
              'candidate',
              contains('hidden by ancestor Opacity'),
            ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectation;
    expect(tapped, isFalse);
  });

  testWidgets(r'$(...).enterText()はTextFieldに入力できる（本番モード原型）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FormScreen()));
    final e = makeTester(tester);

    var done = false;
    e.$(#email).enterText('user@example.com').then((_) => done = true);
    for (var i = 0; i < 5 && !done; i++) {
      signal.tick();
      await tester.pump();
    }

    expect(done, isTrue);
    expect(find.text('user@example.com'), findsOneWidget);
  });

  testWidgets('disabledなTextFieldには入力しない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TextField(key: ValueKey('disabled_input'), enabled: false),
        ),
      ),
    );
    final e = makeTester(tester);

    final expectation = expectLater(
      e
          .$(#disabled_input)
          .enterText('blocked', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<WaitTimeoutException>()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectation;
    expect(find.text('blocked'), findsNothing);
  });

  testWidgets(r'$記法のチェーンでスコープを絞って操作できる', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _FormScreen()));
    final e = makeTester(tester);

    // フォームセクション配下のTextFieldに絞って入力
    var done = false;
    e
        .$(#form_section)
        .$(TextField)
        .enterText('scoped')
        .then((_) => done = true);
    for (var i = 0; i < 5 && !done; i++) {
      signal.tick();
      await tester.pump();
    }

    expect(done, isTrue);
    expect(find.text('scoped'), findsOneWidget);
  });

  testWidgets('存在しない要素へのtapはWaitTimeoutExceptionで失敗する', (tester) async {
    await tester.pumpWidget(counterApp());
    final e = makeTester(tester);

    Object? error;
    // ignore: avoid_types_on_closure_parameters
    e.$(#missing).tap(timeout: const Duration(milliseconds: 50)).catchError((
      Object err,
    ) {
      error = err;
    });
    await tester.pump(const Duration(milliseconds: 100));

    expect(error, isA<ActionabilityTimeoutException>());
    expect('$error', contains('missing'));
    expect('$error', contains('reason: no elements matched the finder'));
    expect('$error', contains('candidates: none'));
  });

  testWidgets('actionability理由と候補をtrace・HTML reportへ保存する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ElevatedButton(
          key: ValueKey('trace_disabled'),
          onPressed: null,
          child: Text('操作不可'),
        ),
      ),
    );
    writer.runStart(runId: 'diagnostic-run', platform: 'ios');
    final testId = writer.testStart('診断できる');
    final e = EndevirTester(
      writer: writer,
      testId: testId,
      frameSignal: signal,
      rootResolver: () => tester.binding.rootElement!,
    );

    final operation = e.step(
      '無効ボタンをタップ',
      () => e.$(#trace_disabled).tap(
        timeout: const Duration(milliseconds: 50),
      ),
    );
    final expectation = expectLater(
      operation,
      throwsA(isA<ActionabilityTimeoutException>()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectation;

    final events = lines.map(traceEventFromJson).toList();
    final stepEnd = events.firstWhere(
      (event) => event.type == TraceEventType.STEP_END,
    );
    expect(stepEnd.error, contains('reason:'));
    expect(stepEnd.error, contains('disabled or ignores pointer events'));
    expect(stepEnd.error, contains('path='));
    expect(stepEnd.error, contains('trace_disabled'));

    writer.testEnd(testId, TraceStatus.FAILED, error: stepEnd.error);
    writer.runEnd();
    final html = buildHtmlReport(
      TraceModel.fromEvents(lines.map(traceEventFromJson).toList()),
    );
    expect(html, contains('disabled or ignores pointer events'));
    expect(html, contains('trace_disabled'));
    expect(html, contains('path='));
  });
}

// --- 証跡（スクリーンショット）統合 ---

void _screenshotTests() {
  late List<String> lines;
  late TraceWriter writer;
  late FakeCapturer capturer;
  late List<String> delivered;
  late EvidenceRecorder recorder;

  setUp(() {
    lines = [];
    writer = TraceWriter(lines.add, nowUs: () => 0);
    capturer = FakeCapturer();
    delivered = [];
    recorder = EvidenceRecorder(
      capturer: capturer,
      deliver: (path, bytes) => delivered.add(path),
    );
  });

  List<TraceEvent> parsed() =>
      lines.map((line) => traceEventFromJson(line)).toList();

  EndevirTester tester(ScreenshotMode mode, {int attempt = 1}) => EndevirTester(
    writer: writer,
    testId: 1,
    evidence: recorder,
    screenshotMode: mode,
    attempt: attempt,
  );

  testWidgets('証跡モード: 成功したstepもスクリーンショットを記録する', (t) async {
    final e = tester(ScreenshotMode.evidence);

    await e.step('手順', () async {});
    capturer.encodes.single.complete([1]);
    await recorder.flush();

    final stepEnd = parsed().firstWhere(
      (ev) => ev.type == TraceEventType.STEP_END,
    );
    expect(stepEnd.screenshot, 'shots/1.png');
    expect(delivered, ['shots/1.png']);
  });

  testWidgets('onFailureモード: 失敗したstepのみ記録する', (t) async {
    final e = tester(ScreenshotMode.onFailure);

    await e.step('成功する手順', () async {});
    await expectLater(
      e.step('失敗する手順', () async => throw StateError('boom')),
      throwsStateError,
    );

    final stepEnds = parsed()
        .where((ev) => ev.type == TraceEventType.STEP_END)
        .toList();
    expect(stepEnds[0].screenshot, isNull);
    expect(stepEnds[1].screenshot, isNotNull);
    expect(capturer.captured, 1);
  });

  testWidgets('onFirstRetryモード: attempt>1でのみ記録する', (t) async {
    await tester(ScreenshotMode.onFirstRetry).step('初回', () async {});
    expect(capturer.captured, 0);

    await tester(
      ScreenshotMode.onFirstRetry,
      attempt: 2,
    ).step('リトライ', () async {});
    expect(capturer.captured, 1);
  });

  testWidgets('noneモード: 記録しない', (t) async {
    await expectLater(
      tester(ScreenshotMode.none).step('失敗', () async => throw StateError('x')),
      throwsStateError,
    );
    expect(capturer.captured, 0);
  });
}

class _FormScreen extends StatelessWidget {
  const _FormScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        key: const ValueKey('form_section'),
        children: const [TextField(key: ValueKey('email'))],
      ),
    );
  }
}

class _CounterScreen extends StatefulWidget {
  const _CounterScreen();

  @override
  State<_CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<_CounterScreen> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('カウント: $_count'),
          ElevatedButton(
            key: const ValueKey('increment'),
            onPressed: () => setState(() => _count++),
            child: const Text('+1'),
          ),
        ],
      ),
    );
  }
}
