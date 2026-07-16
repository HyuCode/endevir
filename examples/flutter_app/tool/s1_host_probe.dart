// M0スパイク S1: ホスト側プローブ。
// アプリ内エージェント（s1_agent.dart）に接続し、レイテンシと操作の成立性を計測する。
//
// 使い方: アプリ（main_s1_agent.dart）をデバイスで起動した状態で
//   fvm dart run tool/s1_host_probe.dart [host] [port]
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : 'localhost';
  final port = args.length > 1 ? int.parse(args[1]) : 8808;
  final base = 'http://$host:$port';
  final client = HttpClient();

  Future<Map<String, dynamic>> get(String path) async {
    final request = await client.getUrl(Uri.parse('$base$path'));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('GET $path -> ${response.statusCode}: $body');
    }
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : {'value': decoded};
  }

  // 1. 接続確立（起動待ちリトライ: 最大30回 x 500ms）
  var connected = false;
  for (var i = 0; i < 30 && !connected; i++) {
    try {
      await get('/ping');
      connected = true;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  if (!connected) {
    stderr.writeln('S1-PROBE FAILED: could not connect to $base');
    exit(1);
  }
  print('S1-PROBE connected to $base');

  // 2. HTTP RTT計測（100回）
  final rtts = <int>[];
  for (var i = 0; i < 100; i++) {
    final sw = Stopwatch()..start();
    await get('/ping');
    rtts.add(sw.elapsedMicroseconds);
  }
  rtts.sort();
  print('S1-METRIC http_rtt_us: '
      'min=${rtts.first} median=${rtts[50]} p95=${rtts[95]} max=${rtts.last}');

  // 3. WebSocket RTT計測（100回エコー）
  final ws = await WebSocket.connect('ws://$host:$port/ws');
  final wsRtts = <int>[];
  final responses = StreamIterator<dynamic>(ws);
  for (var i = 0; i < 100; i++) {
    final sw = Stopwatch()..start();
    ws.add('ping-$i');
    await responses.moveNext();
    wsRtts.add(sw.elapsedMicroseconds);
  }
  await ws.close();
  wsRtts.sort();
  print('S1-METRIC ws_rtt_us: '
      'min=${wsRtts.first} median=${wsRtts[50]} p95=${wsRtts[95]} max=${wsRtts.last}');

  // 4. 実操作シナリオ: 無限アニメーション画面へ遷移→カウントアップ→検証
  Future<void> waitForText(String value) async {
    for (var i = 0; i < 50; i++) {
      final result = await get('/text?value=${Uri.encodeQueryComponent(value)}');
      if (result['exists'] == true) return;
      // スパイクのためホスト側は素朴なポーリング。本番はS3の待機器がアプリ内で待つ
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('text not found: $value');
  }

  final scenarioSw = Stopwatch()..start();
  final tap1 = await get('/tap?key=nav_infinite_animation');
  if (tap1['ok'] != true) throw StateError('tap failed: $tap1');
  await waitForText('カウント: 0');
  final tap2 = await get('/tap?key=increment_button');
  if (tap2['ok'] != true) throw StateError('tap failed: $tap2');
  await waitForText('カウント: 1');
  print('S1-METRIC scenario_nav_tap_verify_ms: ${scenarioSw.elapsedMilliseconds}');

  // 5. キー列挙（ツリーアクセスの確認）
  final request = await client.getUrl(Uri.parse('$base/keys'));
  final response = await request.close();
  final keys = jsonDecode(await response.transform(utf8.decoder).join()) as List;
  print('S1-METRIC visible_keys: ${keys.length} $keys');

  client.close();
  print('S1-PROBE all checks passed');
}
