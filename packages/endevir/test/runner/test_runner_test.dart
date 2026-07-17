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
        testerFactory: (testId) =>
            EndevirTester(writer: writer, testId: testId),
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
}
