import 'package:endevir/endevir.dart';

void main() {
  endevirTest('ホーム画面が表示される', (e) async {
    await e.expectVisible('Endevir Example');
  });
}
