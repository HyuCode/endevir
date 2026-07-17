// `endevir test`: ビルド→インストール→起動→エージェント接続→実行→trace回収。
// M1縦の貫通の実装。デバイス管理はiOSシミュレータ（simctl）と
// Androidエミュレータ/実機（adb）をサポートする。
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:yaml/yaml.dart';

import 'enumerate.dart';
import 'init_command.dart' show writeBundle;

const _agentPort = 8808;

/// プロジェクトルートの endevir.yaml から実行設定を読む（CORE-103）。
EndevirRunConfig loadRunConfig({String path = 'endevir.yaml'}) {
  final file = File(path);
  if (!file.existsSync()) return const EndevirRunConfig();
  final yaml = loadYaml(file.readAsStringSync());
  if (yaml is! Map) return const EndevirRunConfig();
  return EndevirRunConfig.fromYamlMap(yaml);
}

Future<int> runTestCommand(List<String> args) async {
  final parser = ArgParser()
    ..addOption('platform',
        abbr: 'p', allowed: ['ios', 'android'], help: '実行プラットフォーム')
    ..addOption('device', abbr: 'd', help: 'シミュレータUDID / adbシリアル')
    ..addOption('target',
        abbr: 't',
        defaultsTo: 'endevir_test/main_test.dart',
        help: 'テストエントリポイント')
    ..addOption('out', defaultsTo: '.endevir', help: 'trace出力ディレクトリ')
    ..addOption('only', help: '実行するテスト名（完全一致）')
    ..addFlag('help', abbr: 'h', negatable: false);

  final options = parser.parse(args);
  if (options['help'] as bool) {
    print('usage: endevir test -p <ios|android> -d <device> [-t target]');
    print(parser.usage);
    return 0;
  }
  final platform = options['platform'] as String?;
  final device = options['device'] as String?;
  if (platform == null || device == null) {
    stderr.writeln('error: --platform と --device は必須です');
    return 64;
  }

  final target = options['target'] as String;
  final outDir = Directory(options['out'] as String);

  // ビルド時テスト列挙+バンドル再生成（CORE-104/110、ADR-005）
  if (Directory('endevir_test').existsSync()) {
    final enumeration = enumerateTests('endevir_test');
    for (final warning in enumeration.warnings) {
      print('[endevir] WARNING: $warning');
    }
    writeBundle(enumeration);
    outDir.createSync(recursive: true);
    File('${outDir.path}/test_manifest.json').writeAsStringSync(jsonEncode([
      for (final entry in enumeration.entries)
        {'fullName': entry.fullName, 'file': entry.file},
    ]));
    print('[endevir] ${enumeration.entries.length} tests '
        'in ${enumeration.files.length} files (bundle regenerated)');
  }

  print('[endevir] build ($platform, target: $target)');
  final launcher = platform == 'ios'
      ? _IosSimulatorLauncher(device)
      : _AndroidLauncher(device);
  await launcher.build(target);

  print('[endevir] install & launch');
  await launcher.installAndLaunch();

  try {
    print('[endevir] connect to agent');
    final socket = await connectToAgent(host: launcher.agentHost);

    final exitCode = await runAndCollect(
      socket,
      outDir: outDir,
      only: options['only'] as String?,
      config: loadRunConfig(),
    );
    await socket.close();
    return exitCode;
  } finally {
    await launcher.terminate();
  }
}

/// エージェントへの接続（リトライつき）。develop/testコマンドから共用する。
Future<WebSocket> connectToAgent({String host = 'localhost'}) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    try {
      return await WebSocket.connect('ws://$host:$_agentPort/ws');
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  throw StateError('agent not reachable on $host:$_agentPort');
}

Future<int> runAndCollect(
  WebSocket socket, {
  required Directory outDir,
  String? only,
  required EndevirRunConfig config,
}) async {
  outDir.createSync(recursive: true);
  final traceFile = File('${outDir.path}/trace.jsonl');
  final sink = traceFile.openWrite();

  final events = <TraceEvent>[];
  final completer = Completer<RpcResponse>();
  socket.listen((data) {
    final message = RpcMessage.decode(data as String);
    if (message is RpcNotification && message.method == 'traceEvent') {
      final line = message.params['line'] as String;
      sink.writeln(line);
      events.add(traceEventFromJson(line));
      _printProgress(events.last);
    } else if (message is RpcResponse) {
      completer.complete(message);
    }
  });

  print('[endevir] run tests');
  socket.add(RpcRequest(
    id: 1,
    method: 'run',
    params: {'only': ?only, 'config': config.toMap()},
  ).encode());

  final response = await completer.future;
  await sink.flush();
  await sink.close();

  if (response.error != null) {
    stderr.writeln('[endevir] run failed: ${response.error}');
    return 1;
  }
  final reportFile = File('${outDir.path}/report.html');
  reportFile.writeAsStringSync(buildHtmlReport(TraceModel.fromEvents(events)));

  final result = response.result!;
  final failed = result['failed'] as int;
  final flaky = result['flaky'] as int? ?? 0;
  print('');
  print('[endevir] ${result['total']} tests: '
      '${result['passed']} passed, $failed failed'
      '${flaky > 0 ? ' ($flaky flaky)' : ''}');
  print('[endevir] trace:  ${traceFile.path}');
  print('[endevir] report: ${reportFile.path}');
  return failed > 0 ? 1 : 0;
}

void _printProgress(TraceEvent event) {
  switch (event.type) {
    case TraceEventType.TEST_START:
      stdout.write('  ${event.name} ... ');
    case TraceEventType.TEST_END:
      print(event.status == TraceStatus.PASSED
          ? 'ok (${(event.durationUs ?? 0) ~/ 1000}ms)'
          : 'FAILED: ${event.error ?? ''}');
    default:
      break;
  }
}

/// プロジェクトが fvm を使っていれば `fvm flutter`、なければ `flutter`。
Future<void> _flutter(List<String> args) async {
  final useFvm = File('.fvmrc').existsSync() || File('../../.fvmrc').existsSync();
  final executable = useFvm ? 'fvm' : 'flutter';
  final fullArgs = useFvm ? ['flutter', ...args] : args;
  final process = await Process.start(executable, fullArgs,
      mode: ProcessStartMode.inheritStdio);
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, fullArgs, 'flutter failed', code);
  }
}

Future<ProcessResult> _run(String executable, List<String> args,
    {bool check = true}) async {
  final result = await Process.run(executable, args);
  if (check && result.exitCode != 0) {
    throw ProcessException(
        executable, args, '${result.stdout}\n${result.stderr}', result.exitCode);
  }
  return result;
}

abstract class _Launcher {
  Future<void> build(String target);
  Future<void> installAndLaunch();
  Future<void> terminate();

  /// エージェントへの到達ホスト（ポートフォワード込み）。
  String get agentHost => 'localhost';
}

class _IosSimulatorLauncher extends _Launcher {
  _IosSimulatorLauncher(this.udid);

  final String udid;
  static const _appPath = 'build/ios/iphonesimulator/Runner.app';
  String? _bundleId;

  @override
  Future<void> build(String target) =>
      _flutter(['build', 'ios', '--simulator', '--debug', '-t', target]);

  @override
  Future<void> installAndLaunch() async {
    final plist = await _run('/usr/libexec/PlistBuddy',
        ['-c', 'Print CFBundleIdentifier', '$_appPath/Info.plist']);
    _bundleId = (plist.stdout as String).trim();

    await _run('xcrun', ['simctl', 'bootstatus', udid, '-b']);
    await _run('xcrun', ['simctl', 'install', udid, _appPath]);
    await _run('xcrun', ['simctl', 'terminate', udid, _bundleId!],
        check: false);
    await _run('xcrun', ['simctl', 'launch', udid, _bundleId!]);
  }

  @override
  Future<void> terminate() async {
    if (_bundleId != null) {
      await _run('xcrun', ['simctl', 'terminate', udid, _bundleId!],
          check: false);
    }
  }
}

class _AndroidLauncher extends _Launcher {
  _AndroidLauncher(this.serial);

  final String serial;
  static const _apkPath = 'build/app/outputs/flutter-apk/app-debug.apk';
  String? _packageName;

  @override
  Future<void> build(String target) =>
      _flutter(['build', 'apk', '--debug', '-t', target]);

  @override
  Future<void> installAndLaunch() async {
    _packageName = _readApplicationId();
    await _run('adb', ['-s', serial, 'install', '-r', _apkPath]);
    await _run('adb', ['-s', serial, 'shell', 'am', 'force-stop', _packageName!],
        check: false);
    await _run('adb', [
      '-s', serial, 'shell', 'am', 'start',
      '-n', '$_packageName/.MainActivity',
    ]);
    await _run('adb',
        ['-s', serial, 'forward', 'tcp:$_agentPort', 'tcp:$_agentPort']);
  }

  @override
  Future<void> terminate() async {
    if (_packageName != null) {
      await _run(
          'adb', ['-s', serial, 'shell', 'am', 'force-stop', _packageName!],
          check: false);
    }
    await _run('adb', ['-s', serial, 'forward', '--remove', 'tcp:$_agentPort'],
        check: false);
  }

  String _readApplicationId() {
    for (final name in [
      'android/app/build.gradle.kts',
      'android/app/build.gradle',
    ]) {
      final file = File(name);
      if (!file.existsSync()) continue;
      final match = RegExp('applicationId\\s*=?\\s*"([^"]+)"')
          .firstMatch(file.readAsStringSync());
      if (match != null) return match.group(1)!;
    }
    throw StateError('applicationId が android/app/build.gradle(.kts) に見つかりません');
  }
}
