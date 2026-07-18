import 'dart:io';

import 'package:endevir_cli/src/stage_retry.dart';
import 'package:endevir_cli/src/test_command.dart';
import 'package:test/test.dart';

void main() {
  Future<void> noDelay(Duration _) async {}

  group('runCliStage', () {
    test('一時エラーを再試行して成功する', () async {
      var attempts = 0;
      final retries = <int>[];

      final value = await runCliStage<String>(
        stage: CliStage.install,
        operation: () async {
          attempts++;
          if (attempts == 1) {
            throw const ProcessException('adb', ['install'], 'offline');
          }
          return 'ok';
        },
        retryIf: (error) => error is ProcessException,
        delay: noDelay,
        onRetry: (_, failedAttempt, _, _) => retries.add(failedAttempt),
      );

      expect(value, 'ok');
      expect(attempts, 2);
      expect(retries, [1]);
    });

    test('再試行上限で段階別終了コードを返す', () async {
      final future = runCliStage<void>(
        stage: CliStage.launch,
        operation: () async => throw StateError('launch rejected'),
        retryIf: (_) => true,
        maxAttempts: 3,
        delay: noDelay,
      );

      await expectLater(
        future,
        throwsA(
          isA<CliStageException>()
              .having((error) => error.stage, 'stage', CliStage.launch)
              .having((error) => error.attempts, 'attempts', 3)
              .having((error) => error.exitCode, 'exitCode', 72)
              .having((error) => error.toString(), 'message',
                  contains('launch failed after 3 attempt(s)')),
        ),
      );
    });

    test('恒久エラーは再試行しない', () async {
      var attempts = 0;
      final future = runCliStage<void>(
        stage: CliStage.install,
        operation: () async {
          attempts++;
          throw ArgumentError('invalid package');
        },
        retryIf: (error) => error is ProcessException,
        maxAttempts: 3,
        delay: noDelay,
      );

      await expectLater(
        future,
        throwsA(isA<CliStageException>().having(
          (error) => error.attempts,
          'attempts',
          1,
        )),
      );
      expect(attempts, 1);
    });
  });

  test('agent接続失敗をexit 73と試行回数つきで報告する', () async {
    var attempts = 0;
    final future = connectToAgent(
      maxAttempts: 3,
      retryDelay: Duration.zero,
      delay: noDelay,
      connector: (_) async {
        attempts++;
        throw const SocketException('connection refused');
      },
    );

    await expectLater(
      future,
      throwsA(
        isA<CliStageException>()
            .having((error) => error.stage, 'stage', CliStage.agentConnect)
            .having((error) => error.attempts, 'attempts', 3)
            .having((error) => error.exitCode, 'exitCode', 73),
      ),
    );
    expect(attempts, 3);
  });
}
