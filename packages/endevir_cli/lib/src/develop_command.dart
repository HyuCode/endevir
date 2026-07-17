// `endevir develop`: 修正→ホットリスタート→テスト再実行のループ（CLI-102）。
//
// ADR-003: ホットリスタートの実体はkernel再コンパイル+DevFS転送を伴うため、
// `flutter run` サブプロセスへのstdinキー送信（R）で実現する（S5で実証、
// ループ1.75〜2.2秒）。VM Service直接接続は将来の最適化として保持。
// ループ秒数（NFR-002のKPI）は毎回計測して表示する。
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'enumerate.dart';
import 'flutter_cli.dart';
import 'init_command.dart' show writeBundle;
import 'test_command.dart' show connectToAgent, loadRunConfig, runAndCollect;

/// 連続イベントをまとめる（エディタの保存は複数の書き込みイベントを出す）。
class Debouncer {
  Debouncer(this.delay, this.action);

  final Duration delay;
  final void Function() action;
  Timer? _timer;

  void trigger() {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

Future<int> runDevelopCommand(List<String> args) async {
  final parser = ArgParser()
    ..addOption('device', abbr: 'd', help: 'デバイスID')
    ..addOption('target',
        abbr: 't', defaultsTo: 'endevir_test/main_test.dart')
    ..addOption('out', defaultsTo: '.endevir')
    ..addOption('only', help: '実行するテスト名（完全一致）')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(args);
  if (options['help'] as bool) {
    print('usage: endevir develop -d <device>');
    print(parser.usage);
    return 0;
  }
  final device = options['device'] as String?;
  if (device == null) {
    stderr.writeln('error: --device は必須です');
    return 64;
  }
  final target = options['target'] as String;
  final outDir = Directory(options['out'] as String)..createSync(recursive: true);
  final only = options['only'] as String?;

  _regenerateBundle();

  // flutter runを起動（ビルド+インストール+起動+アタッチを一括で担う）
  print('[endevir] starting app (flutter run)...');
  final flutterLog = File('${outDir.path}/develop_flutter.log').openWrite();
  final process = await Process.start(
    flutterExecutable(),
    [
      ...flutterArgPrefix(),
      'run',
      '--debug',
      '--machine', // 構造化イベントで起動完了・終了を検知する
      '-t', target,
      '-d', device,
    ],
  );
  final appStarted = Completer<void>();
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    flutterLog.writeln(line);
    if (line.contains('"event":"app.started"') && !appStarted.isCompleted) {
      appStarted.complete();
    }
  });
  process.stderr.transform(utf8.decoder).listen(flutterLog.write);
  // --machineモードのホットリスタートはJSON-RPCコマンドで送る
  var commandId = 0;
  String? appId;
  void sendRestart() {
    process.stdin.writeln(jsonEncode([
      {
        'id': ++commandId,
        'method': 'app.restart',
        'params': {'appId': appId, 'fullRestart': true},
      }
    ]));
  }

  // app.startイベントからappIdを拾う
  final appIdPattern = RegExp(r'"appId":"([^"]+)"');

  Future<void> runTests(String reason) async {
    final loopStopwatch = Stopwatch()..start();
    try {
      final socket = await connectToAgent();
      final exitCode = await runAndCollect(
        socket,
        outDir: outDir,
        only: only,
        config: loadRunConfig(),
      );
      await socket.close();
      print('[endevir] loop: ${loopStopwatch.elapsedMilliseconds}ms '
          '($reason${exitCode == 0 ? '' : ', failures'})');
    } catch (e) {
      print('[endevir] run failed: $e');
    }
    print('[endevir] watching... (r+Enter=再実行, q+Enter=終了)');
  }

  // 初回: アプリ起動を待って実行
  await appStarted.future.timeout(const Duration(minutes: 5));
  // appIdをログから回収（app.startedより前に流れている）
  final logContent =
      await File('${outDir.path}/develop_flutter.log').readAsString();
  appId = appIdPattern.firstMatch(logContent)?.group(1);
  await runTests('initial');

  // ファイル監視 → バンドル再生成 → ホットリスタート → 再実行
  var restartInFlight = false;
  final debouncer = Debouncer(const Duration(milliseconds: 300), () async {
    if (restartInFlight) return;
    restartInFlight = true;
    try {
      final changeStopwatch = Stopwatch()..start();
      _regenerateBundle();
      sendRestart();
      // 再起動後のエージェント復帰はconnectToAgentのリトライが吸収する
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final socket = await connectToAgent();
      final exitCode = await runAndCollect(
        socket,
        outDir: outDir,
        only: only,
        config: loadRunConfig(),
      );
      await socket.close();
      print('[endevir] loop: ${changeStopwatch.elapsedMilliseconds}ms '
          '(file change${exitCode == 0 ? '' : ', failures'})');
      print('[endevir] watching... (r+Enter=再実行, q+Enter=終了)');
    } catch (e) {
      print('[endevir] rerun failed: $e');
    } finally {
      restartInFlight = false;
    }
  });

  final subscriptions = <StreamSubscription<Object?>>[];
  for (final dirName in ['endevir_test', 'lib']) {
    final dir = Directory(dirName);
    if (!dir.existsSync()) continue;
    subscriptions.add(dir.watch(recursive: true).listen((event) {
      if (event.path.endsWith('.dart') && !event.path.endsWith('.g.dart')) {
        debouncer.trigger();
      }
    }));
  }

  // ユーザー操作（行入力）
  final stdinSub = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    switch (line.trim()) {
      case 'r':
        debouncer.trigger();
      case 'q':
        process.kill();
    }
  });

  final exitCode = await process.exitCode;
  debouncer.cancel();
  for (final sub in subscriptions) {
    await sub.cancel();
  }
  await stdinSub.cancel();
  await flutterLog.close();
  return exitCode == 0 ? 0 : exitCode;
}

void _regenerateBundle() {
  if (!Directory('endevir_test').existsSync()) return;
  final enumeration = enumerateTests('endevir_test');
  for (final warning in enumeration.warnings) {
    print('[endevir] WARNING: $warning');
  }
  writeBundle(enumeration);
}
