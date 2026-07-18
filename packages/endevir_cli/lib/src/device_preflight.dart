import 'dart:convert';
import 'dart:io';

typedef DeviceCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

enum DevicePreflightFailure {
  toolUnavailable,
  notFound,
  notReady,
  commandFailed,
}

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
}) async {
  final run = commandRunner ?? Process.run;
  switch (platform) {
    case 'ios':
      await _preflightIos(device, run);
    case 'android':
      await _preflightAndroid(device, run);
    default:
      throw ArgumentError.value(platform, 'platform', 'unsupported platform');
  }
}

Future<void> _preflightIos(String udid, DeviceCommandRunner run) async {
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
}

Future<void> _preflightAndroid(String serial, DeviceCommandRunner run) async {
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
}

String _details(ProcessResult result) {
  final text = '${result.stderr}\n${result.stdout}'.trim();
  return text.isEmpty ? 'exit code ${result.exitCode}' : text;
}
