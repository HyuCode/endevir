import 'package:endevir/src/wait/frame_signal.dart';
import 'package:endevir/src/wait/frame_waiter.dart';
import 'package:endevir/src/wait/wait_exception.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// テスト用の手動フレームシグナル。tick()で「1フレーム終端」を再現する。
class ManualFrameSignal implements FrameSignal {
  final List<void Function()> _pending = [];
  int requestedFrames = 0;

  @override
  void onNextFrame(void Function() callback) => _pending.add(callback);

  @override
  void requestFrame() => requestedFrames++;

  /// 1フレーム分のコールバックを発火する。
  void tick() {
    final callbacks = List.of(_pending);
    _pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  int get pendingCallbacks => _pending.length;
}

void main() {
  group('FrameWaiter.waitUntil', () {
    test('条件が最初から真なら、フレームを待たず即完了する', () async {
      final signal = ManualFrameSignal();
      final waiter = FrameWaiter(signal);

      final result = await waiter.waitUntil(() => true, describe: 'immediate');

      expect(result.evaluations, 1);
      expect(signal.requestedFrames, 0, reason: '不要なフレームを要求しない');
      expect(signal.pendingCallbacks, 0);
    });

    test('Nフレーム後に真になる条件を、フレーム終端の再評価で検知する', () {
      fakeAsync((async) {
        final signal = ManualFrameSignal();
        final waiter = FrameWaiter(signal);
        var framesSeen = 0;

        WaitResult? result;
        waiter
            .waitUntil(() => framesSeen >= 3, describe: 'after 3 frames')
            .then((r) => result = r);
        async.flushMicrotasks();

        expect(result, isNull);
        for (var i = 0; i < 3; i++) {
          framesSeen++;
          signal.tick();
          async.flushMicrotasks();
        }

        expect(result, isNotNull);
        // 初回評価1回 + フレームごとに1回 = 4回
        expect(result!.evaluations, 4);
      });
    });

    test('登録時に1フレーム要求する（静止環境でも初回評価が走る保証）', () {
      fakeAsync((async) {
        final signal = ManualFrameSignal();
        final waiter = FrameWaiter(signal);

        waiter.waitUntil(() => false, describe: 'never').ignore();
        async.flushMicrotasks();

        expect(signal.requestedFrames, greaterThanOrEqualTo(1));
      });
    });

    test('タイムアウト時はWaitTimeoutException（説明と評価回数つき）を投げる', () {
      fakeAsync((async) {
        final signal = ManualFrameSignal();
        final waiter = FrameWaiter(signal);

        Object? error;
        waiter
            .waitUntil(
              () => false,
              timeout: const Duration(seconds: 2),
              describe: 'text: ログイン',
            )
            .catchError((Object e) {
          error = e;
          return const WaitResult(Duration.zero, 0);
        });

        signal.tick(); // 1フレームだけ流す
        async.elapse(const Duration(seconds: 3));

        expect(error, isA<WaitTimeoutException>());
        final timeout = error as WaitTimeoutException;
        expect(timeout.message, contains('text: ログイン'));
        expect(timeout.evaluations, 2, reason: '初回+1フレーム');
      });
    });

    test('完了後はフレームコールバックを登録し続けない（リークしない）', () {
      fakeAsync((async) {
        final signal = ManualFrameSignal();
        final waiter = FrameWaiter(signal);
        var done = false;

        waiter.waitUntil(() => done, describe: 'leak check').ignore();
        async.flushMicrotasks();

        done = true;
        signal.tick();
        async.flushMicrotasks();

        expect(signal.pendingCallbacks, 0);
      });
    });

    test('タイムアウト後はフレームが来ても再評価しない', () {
      fakeAsync((async) {
        final signal = ManualFrameSignal();
        final waiter = FrameWaiter(signal);
        var evaluations = 0;

        waiter
            .waitUntil(
              () {
                evaluations++;
                return false;
              },
              timeout: const Duration(seconds: 1),
              describe: 'no eval after timeout',
            )
            .catchError((Object _) => const WaitResult(Duration.zero, 0));

        async.elapse(const Duration(seconds: 2));
        final countAtTimeout = evaluations;

        signal.tick();
        async.flushMicrotasks();

        expect(evaluations, countAtTimeout);
      });
    });
  });
}
