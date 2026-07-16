// M0スパイク S1: アプリ内エージェント（CORE-105の土台）のプロトタイプ。
//
// テスト対象アプリのプロセス内でHTTP/WebSocketサーバを起動し、ホストからの
// コマンド（要素検索・タップ・テキスト検証）を受け付ける。
// 本番ではプロトコル分離（JSON-RPC等）に発展させる。スパイクでは素のHTTPで
// 成立性とレイテンシを測る。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// アプリ内エージェントを起動する。UIと同一isolateで動き、
/// HttpServerのコールバックはメインイベントループ上で実行されるため
/// ウィジェットツリーへ直接アクセスできる。
Future<HttpServer> startAgent({int port = 8808}) async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  debugPrint('S1-AGENT listening on port $port');
  server.listen(_handleRequest, onError: (Object e) {
    debugPrint('S1-AGENT server error: $e');
  });
  return server;
}

int _pointerId = 0;

Future<void> _handleRequest(HttpRequest request) async {
  try {
    final path = request.uri.path;
    if (path == '/ws') {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        // エコー + サーバ側タイムスタンプ（WS往復レイテンシ計測用）
        socket.add(jsonEncode({
          'echo': message,
          'serverTime': DateTime.now().microsecondsSinceEpoch,
        }));
      });
      return;
    }

    final Object? result = switch (path) {
      '/ping' => {'pong': true},
      '/keys' => _collectKeys(),
      '/tap' => await _tapByKey(request.uri.queryParameters['key']!),
      '/text' => {'exists': _textExists(request.uri.queryParameters['value']!)},
      _ => null,
    };

    if (result == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(result));
    }
  } catch (e) {
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.write(jsonEncode({'error': '$e'}));
  } finally {
    await request.response.close();
  }
}

Element? _findByKeyString(String keyValue) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    final key = element.widget.key;
    if (key is ValueKey<String> && key.value == keyValue) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

List<String> _collectKeys() {
  final keys = <String>[];
  void visit(Element element) {
    final key = element.widget.key;
    if (key is ValueKey<String>) keys.add(key.value);
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return keys;
}

bool _textExists(String value) {
  var exists = false;
  void visit(Element element) {
    if (exists) return;
    final widget = element.widget;
    if (widget is Text && (widget.data?.contains(value) ?? false)) {
      exists = true;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return exists;
}

/// 論理座標でポインタイベントを合成してタップする。
/// WidgetTesterに依存しない、本番モードで動くタップの原型。
Future<Map<String, Object>> _tapByKey(String keyValue) async {
  final element = _findByKeyString(keyValue);
  if (element == null) {
    return {'ok': false, 'reason': 'not found: $keyValue'};
  }
  final renderObject = element.renderObject;
  if (renderObject is! RenderBox || !renderObject.attached) {
    return {'ok': false, 'reason': 'no render box: $keyValue'};
  }
  final center =
      renderObject.localToGlobal(renderObject.size.center(Offset.zero));
  final pointer = ++_pointerId;
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: pointer, position: center),
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: pointer, position: center),
  );
  return {'ok': true, 'x': center.dx, 'y': center.dy};
}
