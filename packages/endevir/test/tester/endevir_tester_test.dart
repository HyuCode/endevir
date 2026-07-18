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

    expect(error, isA<WaitTimeoutException>());
    expect('$error', contains('missing'));
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
