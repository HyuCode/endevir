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

import 'build_cache.dart';
import 'device_preflight.dart';
import 'enumerate.dart';
import 'flutter_cli.dart';
import 'init_command.dart' show writeBundle;
import 'stage_retry.dart';

const _agentPort = 8808;

/// Builds a reusable Endevir test application without installing or launching it.
Future<int> runBuildCommand(List<String> args) async {
  final parser = ArgParser()
    ..addOption('platform',
        abbr: 'p', allowed: ['ios', 'android'], help: 'ビルドプラットフォーム')
    ..addOption('target',
        abbr: 't',
        defaultsTo: 'endevir_test/main_test.dart',
        help: 'テストエントリポイント')
    ..addOption('out', defaultsTo: '.endevir', help: 'build manifest出力先')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(args);
  if (options['help'] as bool) {
    print('usage: endevir build -p <ios|android> [-t target]');
    print(parser.usage);
    return 0;
  }
  final platform = options['platform'] as String?;
  if (platform == null) {
    stderr.writeln('error: --platform は必須です');
    return 64;
  }

  final target = options['target'] as String;
  final outDir = Directory(options['out'] as String);
  _prepareTestBundle(outDir, regenerate: true);
  final launcher = _launcherFor(platform, '');
  try {
    await _buildAndRecord(
      launcher: launcher,
      platform: platform,
      target: target,
      outDir: outDir,
    );
    return 0;
  } on ProcessException catch (error) {
    stderr.writeln('[endevir] build failed: $error');
    return 1;
  }
}

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
    ..addFlag('reuse-build',
        negatable: false, help: '`endevir build`で生成した成果物を再利用')
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
  final reuseBuild = options['reuse-build'] as bool;

  // ビルド時テスト列挙+バンドル再生成（CORE-104/110、ADR-005）
  _prepareTestBundle(outDir, regenerate: !reuseBuild);

  final launcher = _launcherFor(platform, device);
  if (reuseBuild) {
    final validation = validateReusableBuild(
      projectRoot: Directory.current.path,
      outDir: outDir.path,
      platform: platform,
      target: target,
    );
    if (!validation.isValid) {
      stderr.writeln(
          '[endevir] reusable build rejected: ${validation.message}');
      stderr.writeln(
          '[endevir] run `endevir build -p $platform -t $target` first');
      return 66;
    }
    print('[endevir] reuse build: ${launcher.artifactPath}');
  }

  if (!await _runPreflight(platform, device,
      phase: reuseBuild ? 'before install' : 'before build')) {
    return 1;
  }

  try {
    if (!reuseBuild) {
      await _buildAndRecord(
        launcher: launcher,
        platform: platform,
        target: target,
        outDir: outDir,
      );

      if (!await _runPreflight(platform, device, phase: 'after build')) {
        return 1;
      }
    }

    print('[endevir] install');
    await _measureStage<void>('install', () => runCliStage<void>(
          stage: CliStage.install,
          operation: launcher.install,
          retryIf: (error) => error is ProcessException,
          onRetry: _printStageRetry,
        ));

    print('[endevir] launch');
    await _measureStage<void>('launch', () => runCliStage<void>(
          stage: CliStage.launch,
          operation: launcher.launch,
          retryIf: (error) => error is ProcessException,
          onRetry: _printStageRetry,
        ));

    print('[endevir] connect to agent');
    final socket = await _measureStage<WebSocket>(
        'agent connect',
        () => connectToAgent(
              host: launcher.agentHost,
              onRetry: _printStageRetry,
            ));
    try {
      return await _measureStage<int>(
          'test run',
          () => runAndCollect(
                socket,
                outDir: outDir,
                only: options['only'] as String?,
                config: loadRunConfig(),
              ));
    } finally {
      await socket.close();
    }
  } on CliStageException catch (error) {
    stderr.writeln('[endevir] $error');
    return error.exitCode;
  } finally {
    await launcher.terminate();
  }
}

Future<T> _measureStage<T>(String name, Future<T> Function() operation) async {
  final stopwatch = Stopwatch()..start();
  try {
    return await operation();
  } finally {
    print('[endevir] timing: $name ${stopwatch.elapsedMilliseconds}ms');
  }
}

_Launcher _launcherFor(String platform, String device) => platform == 'ios'
    ? _IosSimulatorLauncher(device)
    : _AndroidLauncher(device);

void _prepareTestBundle(Directory outDir, {required bool regenerate}) {
  if (!Directory('endevir_test').existsSync()) return;
  final enumeration = enumerateTests('endevir_test');
  for (final warning in enumeration.warnings) {
    print('[endevir] WARNING: $warning');
  }
  if (regenerate) writeBundle(enumeration);
  outDir.createSync(recursive: true);
  File('${outDir.path}/test_manifest.json').writeAsStringSync(jsonEncode([
    for (final entry in enumeration.entries)
      {'fullName': entry.fullName, 'file': entry.file},
  ]));
  print('[endevir] ${enumeration.entries.length} tests '
      'in ${enumeration.files.length} files '
      '(${regenerate ? 'bundle regenerated' : 'reusing bundled tests'})');
}

Future<void> _buildAndRecord({
  required _Launcher launcher,
  required String platform,
  required String target,
  required Directory outDir,
}) async {
  final stopwatch = Stopwatch()..start();
  print('[endevir] build ($platform, target: $target)');
  await launcher.build(target);
  writeBuildManifest(
    projectRoot: Directory.current.path,
    outDir: outDir.path,
    platform: platform,
    target: target,
    artifactPath: launcher.artifactPath,
  );
  print('[endevir] build ready: ${launcher.artifactPath} '
      '(${stopwatch.elapsedMilliseconds}ms)');
}

void _printStageRetry(
  CliStage stage,
  int failedAttempt,
  int maxAttempts,
  Object error,
) {
  // Agent startup can take many polls. Log the first and every tenth failure;
  // install/launch retries always fit this condition through their first try.
  if (failedAttempt == 1 || failedAttempt % 10 == 0) {
    stderr.writeln('[endevir] ${stage.label} attempt $failedAttempt/'
        '$maxAttempts failed; retrying: $error');
  }
}

Future<bool> _runPreflight(
  String platform,
  String device, {
  required String phase,
}) async {
  print('[endevir] device preflight ($phase)');
  try {
    await preflightDevice(platform: platform, device: device);
    return true;
  } on DevicePreflightException catch (error) {
    stderr.writeln('[endevir] device preflight failed ($phase): $error');
    return false;
  }
}

/// エージェントへの接続（リトライつき）。develop/testコマンドから共用する。
Future<WebSocket> connectToAgent({
  String host = 'localhost',
  int maxAttempts = 60,
  Duration retryDelay = const Duration(milliseconds: 500),
  Future<WebSocket> Function(String url)? connector,
  RetryDelay delay = Future<void>.delayed,
  RetryListener? onRetry,
}) =>
    runCliStage<WebSocket>(
      stage: CliStage.agentConnect,
      operation: () =>
          (connector ?? WebSocket.connect)('ws://$host:$_agentPort/ws'),
      retryIf: (_) => true,
      maxAttempts: maxAttempts,
      retryDelay: retryDelay,
      delay: delay,
      onRetry: onRetry,
    );

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
    } else if (message is RpcNotification &&
        message.method == 'screenshot') {
      // スクリーンショットを保存（パスはtraceのstepEnd.screenshotと対応する）
      final file =
          File('${outDir.path}/${message.params['path'] as String}');
      file
        ..createSync(recursive: true)
        ..writeAsBytesSync(base64Decode(message.params['base64'] as String));
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
  reportFile.writeAsStringSync(buildHtmlReport(
    TraceModel.fromEvents(events),
    resolveScreenshot: (path) {
      final file = File('${outDir.path}/$path');
      return file.existsSync() ? file.readAsBytesSync() : null;
    },
  ));

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

/// flutterコマンドを実行する（fvm対応はflutter_cli.dartで解決）。
Future<void> _flutter(List<String> args) async {
  final executable = flutterExecutable();
  final fullArgs = [...flutterArgPrefix(), ...args];
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
  String get artifactPath;
  Future<void> build(String target);
  Future<void> install();
  Future<void> launch();
  Future<void> terminate();

  /// エージェントへの到達ホスト（ポートフォワード込み）。
  String get agentHost => 'localhost';
}

class _IosSimulatorLauncher extends _Launcher {
  _IosSimulatorLauncher(this.udid);

  final String udid;
  static const _appPath = 'build/ios/iphonesimulator/Runner.app';
  String? _bundleId;
  bool _launchedByCli = false;

  @override
  String get artifactPath => _appPath;

  @override
  Future<void> build(String target) =>
      _flutter(['build', 'ios', '--simulator', '--debug', '-t', target]);

  @override
  Future<void> install() async {
    final plist = await _run('/usr/libexec/PlistBuddy',
        ['-c', 'Print CFBundleIdentifier', '$_appPath/Info.plist']);
    _bundleId = (plist.stdout as String).trim();

    await _run('xcrun', ['simctl', 'bootstatus', udid, '-b']);
    await _run('xcrun', ['simctl', 'install', udid, _appPath]);
  }

  @override
  Future<void> launch() async {
    await _run('xcrun', ['simctl', 'terminate', udid, _bundleId!],
        check: false);
    await _run('xcrun', ['simctl', 'launch', udid, _bundleId!]);
    _launchedByCli = true;
  }

  @override
  Future<void> terminate() async {
    if (_launchedByCli && _bundleId != null) {
      await _run('xcrun', ['simctl', 'terminate', udid, _bundleId!],
          check: false);
      _launchedByCli = false;
    }
  }
}

class _AndroidLauncher extends _Launcher {
  _AndroidLauncher(this.serial);

  final String serial;
  static const _apkPath = 'build/app/outputs/flutter-apk/app-debug.apk';
  String? _packageName;
  bool _launchedByCli = false;
  bool _forwardedByCli = false;

  @override
  String get artifactPath => _apkPath;

  @override
  Future<void> build(String target) =>
      _flutter(['build', 'apk', '--debug', '-t', target]);

  @override
  Future<void> install() async {
    _packageName = _readApplicationId();
    await _run('adb', ['-s', serial, 'install', '-r', _apkPath]);
  }

  @override
  Future<void> launch() async {
    await _run('adb', ['-s', serial, 'shell', 'am', 'force-stop', _packageName!],
        check: false);
    await _run('adb', [
      '-s', serial, 'shell', 'am', 'start',
      '-n', '$_packageName/.MainActivity',
    ]);
    _launchedByCli = true;
    await _run('adb',
        ['-s', serial, 'forward', 'tcp:$_agentPort', 'tcp:$_agentPort']);
    _forwardedByCli = true;
  }

  @override
  Future<void> terminate() async {
    if (_launchedByCli && _packageName != null) {
      await _run(
          'adb', ['-s', serial, 'shell', 'am', 'force-stop', _packageName!],
          check: false);
      _launchedByCli = false;
    }
    if (_forwardedByCli) {
      await _run(
          'adb', ['-s', serial, 'forward', '--remove', 'tcp:$_agentPort'],
          check: false);
      _forwardedByCli = false;
    }
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
