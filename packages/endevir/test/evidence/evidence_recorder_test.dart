import 'dart:async';

import 'package:endevir/src/evidence/evidence_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// エンコード完了を手動制御できる偽キャプチャラ。
class FakeCapturer implements FrameCapturer {
  final List<Completer<List<int>>> encodes = [];
  int captured = 0;

  @override
  Future<CapturedFrame> capture() async {
    captured++;
    final completer = Completer<List<int>>();
    encodes.add(completer);
    return _FakeFrame(completer.future);
  }
}

class _FakeFrame implements CapturedFrame {
  _FakeFrame(this._bytes);
  final Future<List<int>> _bytes;

  @override
  Future<List<int>> encodePng() => _bytes;
}

void main() {
  group('EvidenceRecorder（ADR-004: 同期はスナップショットのみ、エンコードは遅延）', () {
    test('captureForStepはエンコード完了を待たずにパスを返す', () async {
      final capturer = FakeCapturer();
      final delivered = <String>[];
      final recorder = EvidenceRecorder(
        capturer: capturer,
        deliver: (path, bytes) => delivered.add(path),
      );

      final path = await recorder.captureForStep(3);

      expect(path, 'shots/3.png');
      expect(capturer.captured, 1);
      expect(delivered, isEmpty, reason: 'エンコード未完了なので未配送');
    });

    test('flushで全ての遅延エンコードが配送される', () async {
      final capturer = FakeCapturer();
      final delivered = <(String, List<int>)>[];
      final recorder = EvidenceRecorder(
        capturer: capturer,
        deliver: (path, bytes) => delivered.add((path, bytes)),
      );

      await recorder.captureForStep(1);
      await recorder.captureForStep(2);
      capturer.encodes[0].complete([1, 2, 3]);
      capturer.encodes[1].complete([4, 5]);
      await recorder.flush();

      expect(delivered, hasLength(2));
      expect(delivered[0].$1, 'shots/1.png');
      expect(delivered[0].$2, [1, 2, 3]);
      expect(delivered[1].$1, 'shots/2.png');
      expect(delivered[1].$2, [4, 5]);
    });

    test('1件のエンコード失敗は他の配送を妨げない', () async {
      final capturer = FakeCapturer();
      final delivered = <String>[];
      final recorder = EvidenceRecorder(
        capturer: capturer,
        deliver: (path, bytes) => delivered.add(path),
      );

      await recorder.captureForStep(1);
      await recorder.captureForStep(2);
      capturer.encodes[0].completeError(StateError('encode boom'));
      capturer.encodes[1].complete([9]);
      await recorder.flush();

      expect(delivered, ['shots/2.png']);
    });

    test('maxPendingを超えると最古のエンコード完了を待つ（有界キュー）', () async {
      final capturer = FakeCapturer();
      final recorder = EvidenceRecorder(
        capturer: capturer,
        deliver: (path, bytes) {},
        maxPending: 1,
      );

      await recorder.captureForStep(1);
      var secondDone = false;
      unawaited(
          recorder.captureForStep(2).then((_) => secondDone = true));
      await Future<void>.delayed(Duration.zero);

      expect(secondDone, isFalse, reason: 'キュー満杯なので最古の完了待ち');
      capturer.encodes[0].complete([1]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(secondDone, isTrue);
    });
  });
}
