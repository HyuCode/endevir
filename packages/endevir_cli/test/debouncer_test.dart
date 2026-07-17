import 'package:endevir_cli/src/develop_command.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('Debouncer', () {
    test('連続イベントは1回にまとめられる（保存連打・エディタの複数書き込み対策）', () {
      fakeAsync((async) {
        var fired = 0;
        final debouncer =
            Debouncer(const Duration(milliseconds: 300), () => fired++);

        debouncer.trigger();
        debouncer.trigger();
        async.elapse(const Duration(milliseconds: 100));
        debouncer.trigger();

        expect(fired, 0, reason: 'まだ静止していない');
        async.elapse(const Duration(milliseconds: 300));
        expect(fired, 1);
      });
    });

    test('静止期間を挟めば再度発火する', () {
      fakeAsync((async) {
        var fired = 0;
        final debouncer =
            Debouncer(const Duration(milliseconds: 300), () => fired++);

        debouncer.trigger();
        async.elapse(const Duration(milliseconds: 400));
        debouncer.trigger();
        async.elapse(const Duration(milliseconds: 400));

        expect(fired, 2);
      });
    });

    test('cancel後は発火しない', () {
      fakeAsync((async) {
        var fired = 0;
        final debouncer =
            Debouncer(const Duration(milliseconds: 300), () => fired++);

        debouncer.trigger();
        debouncer.cancel();
        async.elapse(const Duration(seconds: 1));

        expect(fired, 0);
      });
    });
  });
}
