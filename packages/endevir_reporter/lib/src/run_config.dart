/// 実行設定（CORE-103）。
///
/// ホスト（CLI）が `endevir.yaml` から構築し、run RPCで運び、
/// アプリ内テスターの既定値として注入される。テスト単位のAPI引数
/// （timeout等）はこの既定値をさらに上書きする。
class EndevirRunConfig {
  const EndevirRunConfig({
    this.timeout = const Duration(seconds: 10),
    this.stabilityFrames = 3,
    this.retries = 0,
  });

  /// RPCパラメータ（toMapの形）から復元する。
  factory EndevirRunConfig.fromMap(Map<String, dynamic> map) {
    const defaults = EndevirRunConfig();
    final timeoutMs = map['timeoutMs'] as int?;
    return EndevirRunConfig(
      timeout: timeoutMs != null
          ? Duration(milliseconds: timeoutMs)
          : defaults.timeout,
      stabilityFrames:
          map['stabilityFrames'] as int? ?? defaults.stabilityFrames,
      retries: map['retries'] as int? ?? defaults.retries,
    );
  }

  /// `endevir.yaml` の形（人間が書く単位: 秒）から構築する。
  factory EndevirRunConfig.fromYamlMap(Map<dynamic, dynamic> yaml) {
    const defaults = EndevirRunConfig();
    final timeoutSeconds = yaml['timeoutSeconds'] as int?;
    return EndevirRunConfig(
      timeout: timeoutSeconds != null
          ? Duration(seconds: timeoutSeconds)
          : defaults.timeout,
      stabilityFrames:
          yaml['stabilityFrames'] as int? ?? defaults.stabilityFrames,
      retries: yaml['retries'] as int? ?? defaults.retries,
    );
  }

  /// 待機のデフォルトタイムアウト。
  final Duration timeout;

  /// 位置安定判定に必要な連続不変フレーム数。
  final int stabilityFrames;

  /// テスト単位のリトライ回数（CORE-106。0でリトライなし）。
  final int retries;

  Map<String, dynamic> toMap() => {
        'timeoutMs': timeout.inMilliseconds,
        'stabilityFrames': stabilityFrames,
        'retries': retries,
      };
}
