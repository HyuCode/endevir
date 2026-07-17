// ignore_for_file: avoid_print
// （ログ相関テストでprint捕捉を検証するため）
import 'package:endevir/src/runner/log_correlator.dart';
import 'package:endevir/src/runner/test_registry.dart';
import 'package:endevir/src/runner/test_runner.dart';
import 'package:endevir/src/tester/endevir_tester.dart';
import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> lines;
  late TraceWriter writer;
  late EndevirTestRegistry registry;

  List<TraceEvent> parsed() =>
      lines.map((line) => traceEventFromJson(line)).toList();

  setUp(() {
    lines = [];
    writer = TraceWriter(lines.add, nowUs: () => 0);
    registry = EndevirTestRegistry();
  });

  EndevirTestRunner runner() => EndevirTestRunner(
        writer: writer,
        testerFactory: (testId, attempt) =>
            EndevirTester(writer: writer, testId: testId, attempt: attempt),
      );

  group('EndevirTestRegistry', () {
    test('endevirTestは登録のみ行い、実行はしない', () {
      var executed = false;
      registry.add('t1', (e) async => executed = true);

      expect(registry.entries, hasLength(1));
      expect(registry.entries.single.name, 't1');
      expect(executed, isFalse);
    });

    test('groupは名前を「group > test」形式で修飾する', () {
      registry.group('ログイン', () {
        registry.add('成功する', (e) async {});
      });
      registry.add('単独', (e) async {});

      expect(registry.entries.map((e) => e.name),
          ['ログイン > 成功する', '単独']);
    });

    test('同名テストの登録はエラーになる', () {
      registry.add('dup', (e) async {});
      expect(() => registry.add('dup', (e) async {}), throwsArgumentError);
    });
  });

  group('EndevirTestRunner.run', () {
    test('runStart/testStart/testEnd/runEndが記録され、成功はpassedになる', () async {
      registry.add('成功するテスト', (e) async {});

      final summary = await runner()
          .run(registry, runId: 'run-1', platform: 'android');

      final events = parsed();
      expect(events.map((e) => e.type).toList(), [
        TraceEventType.RUN_START,
        TraceEventType.TEST_START,
        TraceEventType.TEST_END,
        TraceEventType.RUN_END,
      ]);
      expect(events[2].status, TraceStatus.PASSED);
      expect(summary.total, 1);
      expect(summary.failed, 0);
    });

    test('本文が例外を投げたテストはfailedとしてエラー詳細つきで記録される', () async {
      registry.add('落ちるテスト', (e) async => throw StateError('boom'));
      registry.add('後続テスト', (e) async {});

      final summary = await runner()
          .run(registry, runId: 'run-1', platform: 'android');

      final ends = parsed()
          .where((e) => e.type == TraceEventType.TEST_END)
          .toList();
      expect(ends[0].status, TraceStatus.FAILED);
      expect(ends[0].error, contains('boom'));
      // 失敗しても後続テストは実行される
      expect(ends[1].status, TraceStatus.PASSED);
      expect(summary.failed, 1);
      expect(summary.passed, 1);
    });

    test('e.stepはstepStart/stepEndとしてテストに紐づいて記録される', () async {
      registry.add('ステップつき', (e) async {
        await e.step('手順1', () async {});
        await e.step('手順2', () async {});
      });

      await runner().run(registry, runId: 'r', platform: 'ios');

      final events = parsed();
      final testId = events
          .firstWhere((e) => e.type == TraceEventType.TEST_START)
          .testId;
      final stepStarts =
          events.where((e) => e.type == TraceEventType.STEP_START).toList();
      expect(stepStarts.map((e) => e.name), ['手順1', '手順2']);
      expect(stepStarts.map((e) => e.testId), everyElement(testId));
      expect(
        events.where((e) => e.type == TraceEventType.STEP_END).map(
              (e) => e.status,
            ),
        everyElement(TraceStatus.PASSED),
      );
    });

    test('step内の例外はstepEnd failedとして記録され、テストも失敗する', () async {
      registry.add('ステップで落ちる', (e) async {
        await e.step('壊れる手順', () async => throw StateError('step boom'));
      });

      await runner().run(registry, runId: 'r', platform: 'ios');

      final events = parsed();
      final stepEnd =
          events.firstWhere((e) => e.type == TraceEventType.STEP_END);
      expect(stepEnd.status, TraceStatus.FAILED);
      expect(stepEnd.error, contains('step boom'));
      final testEnd =
          events.firstWhere((e) => e.type == TraceEventType.TEST_END);
      expect(testEnd.status, TraceStatus.FAILED);
    });

    test('retries指定時、失敗したテストは再試行され、成功すればflakyとして数えられる', () async {
      var attempts = 0;
      registry.add('2回目で成功する', (e) async {
        attempts++;
        if (attempts < 2) throw StateError('flake');
      });

      final summary = await runner().run(registry,
          runId: 'r', platform: 'android', retries: 2);

      expect(attempts, 2);
      expect(summary.passed, 1);
      expect(summary.failed, 0);
      expect(summary.flaky, 1);

      // trace: attempt=1がfailed、attempt=2がpassedとして両方記録される
      final ends =
          parsed().where((e) => e.type == TraceEventType.TEST_END).toList();
      expect(ends, hasLength(2));
      expect(ends[0].attempt, 1);
      expect(ends[0].status, TraceStatus.FAILED);
      expect(ends[1].attempt, 2);
      expect(ends[1].status, TraceStatus.PASSED);
    });

    test('リトライを使い切って失敗したテストはfailedになる', () async {
      registry.add('常に失敗する', (e) async => throw StateError('boom'));

      final summary = await runner().run(registry,
          runId: 'r', platform: 'android', retries: 1);

      expect(summary.failed, 1);
      expect(summary.flaky, 0);
      final ends =
          parsed().where((e) => e.type == TraceEventType.TEST_END).toList();
      expect(ends, hasLength(2), reason: '初回+リトライ1回');
      expect(ends.map((e) => e.status), everyElement(TraceStatus.FAILED));
    });

    test('retries=0（既定）ではリトライしない', () async {
      var attempts = 0;
      registry.add('失敗する', (e) async {
        attempts++;
        throw StateError('boom');
      });

      await runner().run(registry, runId: 'r', platform: 'android');

      expect(attempts, 1);
    });

    test('テスト単位のretries指定は実行時設定を上書きする', () async {
      var attempts = 0;
      registry.add('個別設定つき', (e) async {
        attempts++;
        throw StateError('boom');
      }, retries: 2);

      // 実行時はretries=0だが、テスト側の指定が優先される
      await runner().run(registry, runId: 'r', platform: 'android');

      expect(attempts, 3, reason: '初回+リトライ2回');
    });

    test('beforeEachフックが各テストの前に呼ばれる（状態リセット用）', () async {
      final calls = <String>[];
      registry.add('t1', (e) async => calls.add('t1'));
      registry.add('t2', (e) async => calls.add('t2'));

      final withHook = EndevirTestRunner(
        writer: writer,
        testerFactory: (testId, attempt) =>
            EndevirTester(writer: writer, testId: testId, attempt: attempt),
        beforeEach: () async => calls.add('reset'),
      );
      await withHook.run(registry, runId: 'r', platform: 'android');

      expect(calls, ['reset', 't1', 'reset', 't2']);
    });

    test('対象名フィルタを指定すると一致するテストのみ実行される（ネイティブ写像用）',
        () async {
      var ran = <String>[];
      registry.add('a', (e) async => ran.add('a'));
      registry.add('b', (e) async => ran.add('b'));

      final summary = await runner()
          .run(registry, runId: 'r', platform: 'android', only: 'b');

      expect(ran, ['b']);
      expect(summary.total, 1);
    });
  });

  group('ログ相関（RPT-002/405）', () {
    late LogCorrelator correlator;

    EndevirTestRunner correlatedRunner() {
      correlator = LogCorrelator();
      return EndevirTestRunner(
        writer: writer,
        testerFactory: (testId, attempt) => EndevirTester(
          writer: writer,
          testId: testId,
          attempt: attempt,
          logCorrelator: correlator,
        ),
        logCorrelator: correlator,
      );
    }

    test('テスト本文のprintはsource=dartのLOGとしてtraceに記録される', () async {
      registry.add('ログを出すテスト', (e) async {
        print('こんにちはログ');
      });

      await correlatedRunner().run(registry, runId: 'r', platform: 'ios');

      final logs =
          parsed().where((e) => e.type == TraceEventType.LOG).toList();
      expect(logs, hasLength(1));
      expect(logs.single.source, LogSource.DART);
      expect(logs.single.message, 'こんにちはログ');
    });

    test('step内のprintはそのstepIdに相関し、step外はstepIdなしになる', () async {
      registry.add('相関テスト', (e) async {
        print('ステップ外');
        await e.step('手順A', () async {
          print('手順Aの中');
        });
      });

      await correlatedRunner().run(registry, runId: 'r', platform: 'ios');

      final events = parsed();
      final stepId = events
          .firstWhere((e) => e.type == TraceEventType.STEP_START)
          .stepId;
      final logs =
          events.where((e) => e.type == TraceEventType.LOG).toList();
      expect(logs[0].message, 'ステップ外');
      expect(logs[0].stepId, isNull);
      expect(logs[1].message, '手順Aの中');
      expect(logs[1].stepId, stepId);
    });

    test('ネストしたstepでは内側のstepIdに相関し、抜けると外側に戻る', () async {
      registry.add('ネスト', (e) async {
        await e.step('外側', () async {
          await e.step('内側', () async {
            print('内側ログ');
          });
          print('外側ログ');
        });
      });

      await correlatedRunner().run(registry, runId: 'r', platform: 'ios');

      final events = parsed();
      final stepIds = events
          .where((e) => e.type == TraceEventType.STEP_START)
          .map((e) => e.stepId)
          .toList(); // [外側, 内側]
      final logs =
          events.where((e) => e.type == TraceEventType.LOG).toList();
      expect(logs[0].message, '内側ログ');
      expect(logs[0].stepId, stepIds[1]);
      expect(logs[1].message, '外側ログ');
      expect(logs[1].stepId, stepIds[0]);
    });
  });
}
