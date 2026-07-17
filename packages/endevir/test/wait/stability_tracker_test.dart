
import 'package:endevir/src/wait/stability_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StabilityTracker', () {
    test('同一位置がしきい値フレーム数連続すると安定と判定する', () {
      final tracker = StabilityTracker(requiredFrames: 3);
      const position = Offset(10, 20);

      expect(tracker.update(position), isFalse); // 1回目（前回なし）
      expect(tracker.update(position), isFalse); // 連続1
      expect(tracker.update(position), isFalse); // 連続2
      expect(tracker.update(position), isTrue); // 連続3 → 安定
    });

    test('位置が動くと連続カウントがリセットされる', () {
      final tracker = StabilityTracker(requiredFrames: 2);

      tracker.update(const Offset(10, 20));
      tracker.update(const Offset(10, 20)); // 連続1
      expect(tracker.update(const Offset(15, 20)), isFalse); // 移動→リセット
      expect(tracker.update(const Offset(15, 20)), isFalse); // 連続1
      expect(tracker.update(const Offset(15, 20)), isTrue); // 連続2 → 安定
    });

    test('未検出（null）はリセットとして扱い、安定と判定しない', () {
      final tracker = StabilityTracker(requiredFrames: 1);

      tracker.update(const Offset(10, 20));
      expect(tracker.update(null), isFalse);
      expect(tracker.update(null), isFalse, reason: 'nullの連続は安定ではない');
      tracker.update(const Offset(10, 20));
      expect(tracker.update(const Offset(10, 20)), isTrue);
    });
  });
}
