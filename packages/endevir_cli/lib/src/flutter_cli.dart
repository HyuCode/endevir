// flutterコマンドの実行形態の解決（fvm対応）。
import 'dart:io';

bool? _fvmUsable;

/// fvmを使うべきか。.fvmrcが存在し、かつfvmが実行可能な場合のみtrue。
/// CI等の「.fvmrcはあるがfvm未インストール」な環境ではflutterに落ちる。
bool useFvm() {
  if (_fvmUsable != null) return _fvmUsable!;
  final hasConfig =
      File('.fvmrc').existsSync() || File('../../.fvmrc').existsSync();
  if (!hasConfig) return _fvmUsable = false;
  try {
    final result = Process.runSync('fvm', ['--version']);
    return _fvmUsable = result.exitCode == 0;
  } on ProcessException {
    return _fvmUsable = false;
  }
}

String flutterExecutable() => useFvm() ? 'fvm' : 'flutter';

List<String> flutterArgPrefix() => useFvm() ? ['flutter'] : [];
