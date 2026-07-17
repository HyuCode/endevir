import 'dart:async';
import 'dart:io';

import 'package:endevir/src/agent/endevir_agent.dart';
import 'package:endevir/src/runner/test_runner.dart';
import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EndevirAgent agent;
  late List<String?> runCalls; // 記録された only 引数
  late List<EndevirRunConfig?> configCalls; // 記録された config 引数

  setUp(() async {
    runCalls = [];
    configCalls = [];
    agent = EndevirAgent(
      listTests: () => ['テストA', 'グループ > テストB'],
      runTests: ({only, config, required onTraceLine}) async {
        runCalls.add(only);
        configCalls.add(config);
        onTraceLine('{"type":"runStart","seq":1,"timestampUs":0}');
        onTraceLine('{"type":"runEnd","seq":2,"timestampUs":1}');
        return const RunSummary(total: 2, passed: 1, failed: 1);
      },
    );
    await agent.start(port: 0); // エフェメラルポート
  });

  tearDown(() => agent.stop());

  Future<WebSocket> connect() =>
      WebSocket.connect('ws://127.0.0.1:${agent.port}/ws');

  test('pingに応答する', () async {
    final socket = await connect();
    final responses = StreamIterator<dynamic>(socket);

    socket.add(RpcRequest(id: 1, method: 'ping').encode());
    await responses.moveNext();
    final response =
        RpcMessage.decode(responses.current as String) as RpcResponse;

    expect(response.id, 1);
    expect(response.result, {'pong': true});
    await socket.close();
  });

  test('listTestsは登録済みテスト名を返す', () async {
    final socket = await connect();
    final responses = StreamIterator<dynamic>(socket);

    socket.add(RpcRequest(id: 2, method: 'listTests').encode());
    await responses.moveNext();
    final response =
        RpcMessage.decode(responses.current as String) as RpcResponse;

    expect(response.result, {
      'tests': ['テストA', 'グループ > テストB'],
    });
    await socket.close();
  });

  test('runはtraceEvent通知をストリームし、完了時にサマリーを応答する', () async {
    final socket = await connect();
    final messages = <RpcMessage>[];
    final done = Completer<void>();
    socket.listen((data) {
      messages.add(RpcMessage.decode(data as String));
      if (messages.whereType<RpcResponse>().isNotEmpty) done.complete();
    });

    socket.add(RpcRequest(id: 3, method: 'run', params: {'only': 'テストA'})
        .encode());
    await done.future;

    final notifications = messages.whereType<RpcNotification>().toList();
    expect(notifications, hasLength(2));
    expect(notifications.first.method, 'traceEvent');
    expect(notifications.first.params['line'], contains('runStart'));

    final response = messages.whereType<RpcResponse>().single;
    expect(response.id, 3);
    expect(response.result,
        {'total': 2, 'passed': 1, 'failed': 1, 'flaky': 0});
    expect(runCalls, ['テストA']);
    await socket.close();
  });

  test('runのconfigパラメータが実行設定としてハンドラに渡る（CORE-103）', () async {
    final socket = await connect();
    final responses = StreamIterator<dynamic>(socket);

    socket.add(RpcRequest(id: 9, method: 'run', params: {
      'config': {'timeoutMs': 20000, 'stabilityFrames': 5, 'retries': 2},
    }).encode());
    await responses.moveNext();

    final config = configCalls.single!;
    expect(config.timeout, const Duration(seconds: 20));
    expect(config.stabilityFrames, 5);
    expect(config.retries, 2);
    await socket.close();
  });

  test('未知のメソッドはエラー応答になる', () async {
    final socket = await connect();
    final responses = StreamIterator<dynamic>(socket);

    socket.add(RpcRequest(id: 4, method: 'nope').encode());
    await responses.moveNext();
    final response =
        RpcMessage.decode(responses.current as String) as RpcResponse;

    expect(response.error, contains('nope'));
    await socket.close();
  });

  test('壊れたメッセージでも接続は生き続ける', () async {
    final socket = await connect();
    final responses = StreamIterator<dynamic>(socket);

    socket.add('not json at all');
    socket.add(RpcRequest(id: 5, method: 'ping').encode());
    await responses.moveNext();
    final response =
        RpcMessage.decode(responses.current as String) as RpcResponse;

    expect(response.id, 5);
    await socket.close();
  });
}
