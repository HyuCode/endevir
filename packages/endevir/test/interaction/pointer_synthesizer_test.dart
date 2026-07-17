import 'package:endevir/src/interaction/pointer_synthesizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('合成ポインタイベントで実ボタンをタップできる（WidgetTester非依存の原型）',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const ValueKey('btn'),
            onPressed: () => pressed++,
            child: const Text('tap me'),
          ),
        ),
      ),
    ));

    final center = tester.getCenter(find.byKey(const ValueKey('btn')));
    final synthesizer = PointerSynthesizer();
    await synthesizer.tapAt(center);
    await tester.pump();

    expect(pressed, 1);
  });

  testWidgets('連続タップでポインタIDが衝突しない', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(
          onPressed: () => pressed++,
          child: const Text('t'),
        ),
      ),
    ));

    final center = tester.getCenter(find.byType(ElevatedButton));
    final synthesizer = PointerSynthesizer();
    await synthesizer.tapAt(center);
    await tester.pump();
    await synthesizer.tapAt(center);
    await tester.pump();

    expect(pressed, 2);
  });
}
