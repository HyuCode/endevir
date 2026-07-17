import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:test/test.dart';

void main() {
  group('EndevirRunConfig', () {
    test('デフォルト値を持つ', () {
      const config = EndevirRunConfig();

      expect(config.timeout, const Duration(seconds: 10));
      expect(config.stabilityFrames, 3);
      expect(config.retries, 0);
    });

    test('fromMapは部分的な指定を受け付け、残りはデフォルトになる', () {
      final config = EndevirRunConfig.fromMap({'timeoutMs': 5000});

      expect(config.timeout, const Duration(seconds: 5));
      expect(config.stabilityFrames, 3);
      expect(config.retries, 0);
    });

    test('toMap/fromMapが往復する（RPCで運ぶため）', () {
      const original = EndevirRunConfig(
        timeout: Duration(seconds: 30),
        stabilityFrames: 5,
        retries: 2,
      );

      final restored = EndevirRunConfig.fromMap(original.toMap());

      expect(restored.timeout, original.timeout);
      expect(restored.stabilityFrames, original.stabilityFrames);
      expect(restored.retries, original.retries);
    });

    test('fromYamlMapはendevir.yamlの形（秒指定）を受け付ける', () {
      final config = EndevirRunConfig.fromYamlMap({
        'timeoutSeconds': 20,
        'stabilityFrames': 4,
        'retries': 1,
      });

      expect(config.timeout, const Duration(seconds: 20));
      expect(config.stabilityFrames, 4);
      expect(config.retries, 1);
    });

    test('screenshotMode（記録プリセット、RPT-004）を運べる', () {
      expect(const EndevirRunConfig().screenshotMode,
          ScreenshotMode.onFailure); // 既定は失敗時のみ

      final evidence =
          EndevirRunConfig.fromYamlMap({'screenshotMode': 'evidence'});
      expect(evidence.screenshotMode, ScreenshotMode.evidence);

      final roundtrip = EndevirRunConfig.fromMap(
        const EndevirRunConfig(screenshotMode: ScreenshotMode.evidence)
            .toMap(),
      );
      expect(roundtrip.screenshotMode, ScreenshotMode.evidence);
    });

    test('不明なscreenshotModeは既定値にフォールバックする', () {
      final config =
          EndevirRunConfig.fromYamlMap({'screenshotMode': 'unknown'});
      expect(config.screenshotMode, ScreenshotMode.onFailure);
    });
  });
}
