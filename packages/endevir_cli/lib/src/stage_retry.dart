import 'dart:async';

enum CliStage {
  install('install', 71),
  launch('launch', 72),
  agentConnect('agent connect', 73);

  const CliStage(this.label, this.exitCode);

  final String label;
  final int exitCode;
}

class CliStageException implements Exception {
  const CliStageException({
    required this.stage,
    required this.attempts,
    required this.cause,
  });

  final CliStage stage;
  final int attempts;
  final Object cause;

  int get exitCode => stage.exitCode;

  @override
  String toString() =>
      '${stage.label} failed after $attempts attempt(s) '
      '(exit $exitCode): $cause';
}

typedef RetryDelay = Future<void> Function(Duration duration);
typedef RetryListener = void Function(
  CliStage stage,
  int failedAttempt,
  int maxAttempts,
  Object error,
);

Future<T> runCliStage<T>({
  required CliStage stage,
  required Future<T> Function() operation,
  required bool Function(Object error) retryIf,
  int maxAttempts = 2,
  Duration retryDelay = const Duration(milliseconds: 500),
  RetryDelay delay = Future<void>.delayed,
  RetryListener? onRetry,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
  }

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await operation();
    } catch (error) {
      if (attempt == maxAttempts || !retryIf(error)) {
        throw CliStageException(
          stage: stage,
          attempts: attempt,
          cause: error,
        );
      }
      onRetry?.call(stage, attempt, maxAttempts, error);
      await delay(retryDelay);
    }
  }
  throw StateError('unreachable');
}
