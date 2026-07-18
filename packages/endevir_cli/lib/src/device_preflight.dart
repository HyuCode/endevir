import 'dart:convert';
import 'dart:io';

typedef DeviceCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

enum DevicePreflightFailure {
  toolUnavailable,
  notFound,
  notReady,
  insufficientSpace,
  commandFailed,
}

const defaultMinimumFreeBytes = 1024 * 1024 * 1024;

class DevicePreflightException implements Exception {
  const DevicePreflightException(this.failure, this.message);

  final DevicePreflightFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Verifies that the requested device is usable before an expensive build or
/// an install. Run this again after the build to catch devices disconnected
/// while Flutter was compiling the application.
Future<void> preflightDevice({
  required String platform,
  required String device,
  DeviceCommandRunner? commandRunner,
  int minimumFreeBytes = defaultMinimumFreeBytes,
}) async {
  final run = commandRunner ?? Process.run;
  switch (platform) {
    case 'ios':
      await _preflightIos(device, run, minimumFreeBytes);
    case 'android':
      await _preflightAndroid(device, run, minimumFreeBytes);
    default:
      throw ArgumentError.value(platform, 'platform', 'unsupported platform');
  }
}

Future<void> _preflightIos(
  String udid,
  DeviceCommandRunner run,
  int minimumFreeBytes,
) async {
  final ProcessResult result;
  try {
    result = await run('xcrun', ['simctl', 'list', 'devices', '--json']);
  } on ProcessException {
    throw const DevicePreflightException(
      DevicePreflightFailure.toolUnavailable,
      'xcrun/simctl が見つかりません。Xcode Command Line Toolsを確認してください',
    );
  }
  if (result.exitCode != 0) {
    throw DevicePreflightException(
      DevicePreflightFailure.commandFailed,
      'simctlで端末状態を取得できませんでした: ${_details(result)}',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(result.stdout as String);
  } on FormatException {
    throw const DevicePreflightException(
      DevicePreflightFailure.commandFailed,
      'simctlが不正な端末一覧を返しました',
    );
  }
  final devices = decoded is Map ? decoded['devices'] : null;
  Map<Object?, Object?>? matched;
  if (devices is Map) {
    for (final runtimeDevices in devices.values) {
      if (runtimeDevices is! List) continue;
      for (final candidate in runtimeDevices) {
        if (candidate is Map && candidate['udid'] == udid) {
          matched = candidate;
          break;
        }
      }
      if (matched != null) break;
    }
  }
  if (matched == null) {
    throw DevicePreflightException(
      DevicePreflightFailure.notFound,
      'iOSシミュレータ $udid が見つかりません。`xcrun simctl list devices`でUDIDを確認してください',
    );
  }
  final state = matched['state']?.toString() ?? 'unknown';
  if (state != 'Booted') {
    throw DevicePreflightException(
      DevicePreflightFailure.notReady,
      'iOSシミュレータ $udid は起動していません（state: $state）。先にシミュレータを起動してください',
    );
  }

  final dataPath = matched['dataPath']?.toString();
  if (dataPath == null || dataPath.isEmpty) {
    throw const DevicePreflightException(
      DevicePreflightFailure.commandFailed,
      'iOSシミュレータのデータ保存先を取得できませんでした',
    );
  }
  final space = await _runSpaceCheck(
    run,
    'df',
    ['-Pk', dataPath],
    deviceLabel: 'iOSシミュレータ $udid',
  );
  _requireFreeSpace(space, minimumFreeBytes, 'iOSシミュレータ $udid');
}

Future<void> _preflightAndroid(
  String serial,
  DeviceCommandRunner run,
  int minimumFreeBytes,
) async {
  final ProcessResult result;
  try {
    result = await run('adb', ['-s', serial, 'get-state']);
  } on ProcessException {
    throw const DevicePreflightException(
      DevicePreflightFailure.toolUnavailable,
      'adb が見つかりません。Android SDKのplatform-toolsを確認してください',
    );
  }
  final state = (result.stdout as String).trim();
  final details = _details(result);
  if (result.exitCode != 0) {
    final normalized = details.toLowerCase();
    final failure =
        normalized.contains('offline') || normalized.contains('unauthorized')
        ? DevicePreflightFailure.notReady
        : DevicePreflightFailure.notFound;
    throw DevicePreflightException(
      failure,
      'Android端末 $serial に接続できません: $details',
    );
  }
  if (state != 'device') {
    throw DevicePreflightException(
      DevicePreflightFailure.notReady,
      'Android端末 $serial は利用できません（state: ${state.isEmpty ? 'unknown' : state}）',
    );
  }

  final space = await _runSpaceCheck(
    run,
    'adb',
    ['-s', serial, 'shell', 'df', '-Pk', '/data'],
    deviceLabel: 'Android端末 $serial',
  );
  _requireFreeSpace(space, minimumFreeBytes, 'Android端末 $serial');
}

Future<int> _runSpaceCheck(
  DeviceCommandRunner run,
  String executable,
  List<String> arguments, {
  required String deviceLabel,
}) async {
  final ProcessResult result;
  try {
    result = await run(executable, arguments);
  } on ProcessException {
    throw DevicePreflightException(
      DevicePreflightFailure.commandFailed,
      '$deviceLabel の空き容量を取得できませんでした',
    );
  }
  if (result.exitCode != 0) {
    throw DevicePreflightException(
      DevicePreflightFailure.commandFailed,
      '$deviceLabel の空き容量を取得できませんでした: ${_details(result)}',
    );
  }
  final lines = (result.stdout as String)
      .trim()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) {
    throw DevicePreflightException(
      DevicePreflightFailure.commandFailed,
      '$deviceLabel の空き容量出力を解析できませんでした',
    );
  }
  final columns = lines.last.trim().split(RegExp(r'\s+'));
  final availableKilobytes =
      columns.length > 3 ? int.tryParse(columns[3]) : null;
  if (availableKilobytes == null) {
    throw DevicePreflightException(
      DevicePreflightFailure.commandFailed,
      '$deviceLabel の空き容量出力を解析できませんでした',
    );
  }
  return availableKilobytes * 1024;
}

void _requireFreeSpace(int available, int minimum, String deviceLabel) {
  if (available >= minimum) return;
  final availableMiB = available ~/ (1024 * 1024);
  final minimumMiB = minimum ~/ (1024 * 1024);
  throw DevicePreflightException(
    DevicePreflightFailure.insufficientSpace,
    '$deviceLabel の空き容量が不足しています'
    '（${availableMiB}MiB available, ${minimumMiB}MiB required）',
  );
}

String _details(ProcessResult result) {
  final text = '${result.stderr}\n${result.stdout}'.trim();
  return text.isEmpty ? 'exit code ${result.exitCode}' : text;
}
