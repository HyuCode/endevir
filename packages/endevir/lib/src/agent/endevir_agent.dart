import 'dart:async';
import 'dart:io';

import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:flutter/foundation.dart';

import '../runner/test_runner.dart';

/// テスト実行ハンドラ。traceの各行を[onTraceLine]でストリームする。
/// [config]はホストから渡される実行設定（CORE-103）。
typedef RunHandler = Future<RunSummary> Function({
  String? only,
  EndevirRunConfig? config,
  required void Function(String traceLine) onTraceLine,
});

/// アプリ内エージェント（ADR-002）。
///
/// 単一WebSocket常時接続でJSON-RPCを受け付け、テスト一覧・実行・
/// traceイベントのストリーミングをホストに提供する。
/// UIと同一isolateで動き、コールバックはメインイベントループ上で実行される。
class EndevirAgent {
  EndevirAgent({required this.listTests, required this.runTests});

  final List<String> Function() listTests;
  final RunHandler runTests;

  HttpServer? _server;

  /// 起動後の待受ポート（port: 0で起動した場合はエフェメラル）。
  int get port => _server!.port;

  Future<void> start({int port = 8808}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    debugPrint('ENDEVIR-AGENT listening on ${server.port}');
    server.listen(_handleHttp, onError: (Object e) {
      debugPrint('ENDEVIR-AGENT server error: $e');
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleHttp(HttpRequest request) async {
    if (request.uri.path != '/ws') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen(
      (data) => _handleMessage(socket, data),
      onError: (Object e) => debugPrint('ENDEVIR-AGENT ws error: $e'),
    );
  }

  Future<void> _handleMessage(WebSocket socket, dynamic data) async {
    final RpcMessage message;
    try {
      message = RpcMessage.decode(data as String);
    } on FormatException catch (e) {
      // 壊れたメッセージで接続を落とさない（CORE-105: 診断ログを残して継続）
      debugPrint('ENDEVIR-AGENT malformed message ignored: $e');
      return;
    }
    if (message is! RpcRequest) return;

    try {
      final result = await _dispatch(socket, message);
      socket.add(RpcResponse.success(id: message.id, result: result).encode());
    } catch (e) {
      socket.add(RpcResponse.failure(id: message.id, error: '$e').encode());
    }
  }

  Future<Map<String, dynamic>> _dispatch(
    WebSocket socket,
    RpcRequest request,
  ) async {
    switch (request.method) {
      case 'ping':
        return {'pong': true};
      case 'listTests':
        return {'tests': listTests()};
      case 'run':
        final configMap = request.params['config'] as Map<String, dynamic>?;
        final summary = await runTests(
          only: request.params['only'] as String?,
          config:
              configMap != null ? EndevirRunConfig.fromMap(configMap) : null,
          onTraceLine: (line) => socket.add(
            RpcNotification(method: 'traceEvent', params: {'line': line})
                .encode(),
          ),
        );
        return {
          'total': summary.total,
          'passed': summary.passed,
          'failed': summary.failed,
          'flaky': summary.flaky,
        };
      default:
        throw UnsupportedError('unknown method: ${request.method}');
    }
  }
}
