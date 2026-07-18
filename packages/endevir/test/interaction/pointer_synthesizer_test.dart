import 'package:endevir/src/interaction/pointer_synthesizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('合成ポインタイベントで実ボタンをタップできる（WidgetTester非依存の原型）', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('btn'),
              onPressed: () => pressed++,
              child: const Text('tap me'),
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(const ValueKey('btn')));
    final synthesizer = PointerSynthesizer();
    await synthesizer.tapAt(center);
    await tester.pump();

    expect(pressed, 1);
  });

  testWidgets('連続タップでポインタIDが衝突しない', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => pressed++,
            child: const Text('t'),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(ElevatedButton));
    final synthesizer = PointerSynthesizer();
    await synthesizer.tapAt(center);
    await tester.pump();
    await synthesizer.tapAt(center);
    await tester.pump();

    expect(pressed, 2);
  });

  testWidgets('合成ポインタイベントで水平ドラッグできる', (tester) async {
    var distance = 0.0;
    var pointerMoves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Listener(
            onPointerMove: (_) => pointerMoves++,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => distance += details.delta.dx,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final synthesizer = PointerSynthesizer();
    var completed = false;
    synthesizer
        .dragBy(const Offset(300, 300), const Offset(-200, 0))
        .then((_) => completed = true);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();

    expect(completed, isTrue);
    expect(pointerMoves, 12);
    expect(distance, lessThan(-150));
  });
}
