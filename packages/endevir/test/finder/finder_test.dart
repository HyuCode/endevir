import 'package:endevir/src/finder/finder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('EndevirFinder.from', () {
    testWidgets('Symbol（#記法）はValueKey<String>で要素を特定する', (tester) async {
      await tester.pumpWidget(app(Column(children: const [
        Text('hello', key: ValueKey('greeting')),
        Text('world'),
      ])));

      final finder = EndevirFinder.from(#greeting);
      final elements = finder.resolve(tester.binding.rootElement!);

      expect(elements, hasLength(1));
      expect((elements.single.widget as Text).data, 'hello');
    });

    testWidgets('Stringは部分一致でTextウィジェットを特定する', (tester) async {
      await tester.pumpWidget(app(Column(children: const [
        Text('カウント: 0'),
        Text('その他'),
      ])));

      final finder = EndevirFinder.from('カウント');
      final elements = finder.resolve(tester.binding.rootElement!);

      expect(elements, hasLength(1));
      expect((elements.single.widget as Text).data, 'カウント: 0');
    });

    testWidgets('KeyオブジェクトとWidget型でも特定できる', (tester) async {
      await tester.pumpWidget(app(Column(children: const [
        TextField(key: Key('email')),
        Text('label'),
      ])));

      final root = tester.binding.rootElement!;
      expect(
        EndevirFinder.from(const Key('email')).resolve(root),
        hasLength(1),
      );
      expect(EndevirFinder.from(TextField).resolve(root), hasLength(1));
    });

    testWidgets('マッチしない場合は空を返す', (tester) async {
      await tester.pumpWidget(app(const Text('a')));

      expect(
        EndevirFinder.from(#missing).resolve(tester.binding.rootElement!),
        isEmpty,
      );
    });

    test('describeは対象を人間可読に説明する（証跡・エラーメッセージ用）', () {
      expect(EndevirFinder.from(#login).describe(), contains('login'));
      expect(EndevirFinder.from('送信').describe(), contains('送信'));
    });
  });
}
