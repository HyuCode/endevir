import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example_app/main.dart';

void main() {
  testWidgets('ホームに4つの検証シナリオへの導線がある', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.byKey(const Key('nav_delayed_load')), findsOneWidget);
    expect(find.byKey(const Key('nav_animation')), findsOneWidget);
    expect(find.byKey(const Key('nav_infinite_animation')), findsOneWidget);
    expect(find.byKey(const Key('nav_form')), findsOneWidget);
  });

  testWidgets('遅延ロード画面: ローディング表示の後にコンテンツが表示される', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DelayedLoadScreen(delay: Duration(seconds: 2)),
    ));

    expect(find.byKey(const Key('loading_indicator')), findsOneWidget);
    expect(find.byKey(const Key('loaded_content')), findsNothing);

    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('loading_indicator')), findsNothing);
    expect(find.byKey(const Key('loaded_content')), findsOneWidget);
  });

  testWidgets('アニメーション画面: 切り替えでアニメーションが完了しカウントが増える', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnimationScreen()));

    expect(find.text('アニメーション完了: 0回'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle_button')));
    await tester.pumpAndSettle();

    expect(find.text('アニメーション完了: 1回'), findsOneWidget);
  });

  testWidgets('無限アニメーション画面: スピナーが回り続ける中でもカウントアップできる', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InfiniteAnimationScreen()));

    expect(find.byKey(const Key('infinite_spinner')), findsOneWidget);
    expect(find.text('カウント: 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('increment_button')));
    await tester.pump();

    expect(find.text('カウント: 1'), findsOneWidget);
  });

  testWidgets('フォーム画面: 不正な入力でエラー、正しい入力で送信完了が表示される', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FormScreen()));

    await tester.enterText(find.byKey(const Key('email_field')), 'invalid');
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pump();

    expect(find.text('メールアドレスが不正です'), findsOneWidget);
    expect(find.byKey(const Key('submit_result')), findsNothing);

    await tester.enterText(
        find.byKey(const Key('email_field')), 'user@example.com');
    await tester.tap(find.byKey(const Key('submit_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('submit_result')), findsOneWidget);
  });
}
