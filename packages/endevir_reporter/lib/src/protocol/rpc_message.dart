import 'dart:convert';

/// エージェント⇔ホスト間のJSON-RPC風メッセージ（ADR-002）。
///
/// 単一WebSocket常時接続の上で、request/response（id対応）と
/// notification（idなし、traceイベントのストリーミング等）を運ぶ。
///
/// 置き場所について: プロトコル定義はtraceスキーマと同様にホスト（CLI・Cloud）
/// とアプリ内エージェントの共通言語のため、当面pure Dartな本パッケージに置く。
/// 肥大化したらendevir_protocolへの分離を検討する（M2）。
sealed class RpcMessage {
  const RpcMessage();

  /// JSON文字列からメッセージを復元する。
  ///
  /// 形式が不正な場合は[FormatException]を投げる（接続は呼び出し側で維持する）。
  static RpcMessage decode(String data) {
    final Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      rethrow;
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('rpc message must be a JSON object');
    }

    final id = json['id'];
    final method = json['method'];
    if (method is String) {
      final params = (json['params'] as Map<String, dynamic>?) ?? const {};
      return id is int
          ? RpcRequest(id: id, method: method, params: params)
          : RpcNotification(method: method, params: params);
    }
    if (id is int && (json.containsKey('result') || json.containsKey('error'))) {
      final error = json['error'] as String?;
      return error != null
          ? RpcResponse.failure(id: id, error: error)
          : RpcResponse.success(
              id: id,
              result: (json['result'] as Map<String, dynamic>?) ?? const {},
            );
    }
    throw const FormatException('unrecognized rpc message shape');
  }

  String encode();
}

/// 応答を要求するリクエスト。
class RpcRequest extends RpcMessage {
  const RpcRequest({required this.id, required this.method, this.params = const {}});

  final int id;
  final String method;
  final Map<String, dynamic> params;

  @override
  String encode() =>
      jsonEncode({'id': id, 'method': method, 'params': params});
}

/// リクエストへの応答。
class RpcResponse extends RpcMessage {
  const RpcResponse.success({required this.id, required Map<String, dynamic> this.result})
      : error = null;

  const RpcResponse.failure({required this.id, required String this.error})
      : result = null;

  final int id;
  final Map<String, dynamic>? result;
  final String? error;

  @override
  String encode() => jsonEncode({
        'id': id,
        if (error != null) 'error': error else 'result': result,
      });
}

/// 応答不要の通知（traceイベントのストリーミング等）。
class RpcNotification extends RpcMessage {
  const RpcNotification({required this.method, this.params = const {}});

  final String method;
  final Map<String, dynamic> params;

  @override
  String encode() => jsonEncode({'method': method, 'params': params});
}
