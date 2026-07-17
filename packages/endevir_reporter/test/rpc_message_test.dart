import 'package:endevir_reporter/endevir_reporter.dart';
import 'package:test/test.dart';

void main() {
  group('RpcMessage', () {
    test('requestのエンコード/デコードが往復する', () {
      final request = RpcRequest(id: 1, method: 'run', params: {'only': 'x'});
      final decoded = RpcMessage.decode(request.encode());

      expect(decoded, isA<RpcRequest>());
      final r = decoded as RpcRequest;
      expect(r.id, 1);
      expect(r.method, 'run');
      expect(r.params, {'only': 'x'});
    });

    test('成功responseの往復', () {
      final response = RpcResponse.success(id: 2, result: {'passed': 3});
      final decoded = RpcMessage.decode(response.encode()) as RpcResponse;

      expect(decoded.id, 2);
      expect(decoded.result, {'passed': 3});
      expect(decoded.error, isNull);
    });

    test('エラーresponseの往復', () {
      final response = RpcResponse.failure(id: 3, error: 'method not found');
      final decoded = RpcMessage.decode(response.encode()) as RpcResponse;

      expect(decoded.id, 3);
      expect(decoded.error, 'method not found');
      expect(decoded.result, isNull);
    });

    test('notification（idなし）の往復', () {
      final notification =
          RpcNotification(method: 'traceEvent', params: {'line': '{}'});
      final decoded = RpcMessage.decode(notification.encode());

      expect(decoded, isA<RpcNotification>());
      final n = decoded as RpcNotification;
      expect(n.method, 'traceEvent');
      expect(n.params['line'], '{}');
    });

    test('不正なJSONはFormatExceptionを投げる', () {
      expect(() => RpcMessage.decode('not json'), throwsFormatException);
      expect(() => RpcMessage.decode('{"noMethod": true}'),
          throwsFormatException);
    });
  });
}
