import 'package:endevir/src/interaction/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('popToRootは積まれたルートをすべて戻す（テスト間リセット）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('詳細画面')),
            ),
          ),
          child: const Text('進む'),
        ),
      ),
    ));

    await tester.tap(find.text('進む'));
    await tester.pumpAndSettle();
    expect(find.text('詳細画面'), findsOneWidget);

    popToRoot(root: tester.binding.rootElement);
    await tester.pumpAndSettle();

    expect(find.text('詳細画面'), findsNothing);
    expect(find.text('進む'), findsOneWidget);
  });

  testWidgets('ルートにいる場合は何もしない', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('ホーム')));

    popToRoot(root: tester.binding.rootElement);
    await tester.pump();

    expect(find.text('ホーム'), findsOneWidget);
  });
}
