import 'package:flutter/widgets.dart';

/// 要素の「探し方の記述」（CORE-002/003）。
///
/// Playwrightのlocator同様に遅延評価であり、[resolve]が呼ばれるたびに
/// 現在のツリーを検索する。要素への参照を保持しない。
abstract class EndevirFinder {
  const EndevirFinder();

  /// ターゲット表現からファインダーを構築する。
  ///
  /// - [Symbol]（`#emailField`記法）: `ValueKey<String>` として解決
  /// - [Key]: ウィジェットキー
  /// - [String]: Textウィジェットの部分一致
  /// - [Type]: ウィジェット型
  /// - [EndevirFinder]: そのまま返す
  factory EndevirFinder.from(Object target) {
    return switch (target) {
      final EndevirFinder finder => finder,
      final Symbol symbol => KeyFinder(ValueKey<String>(_symbolName(symbol))),
      final Key key => KeyFinder(key),
      final String text => TextFinder(text),
      final Type type => TypeFinder(type),
      _ => throw ArgumentError.value(
          target,
          'target',
          'Symbol / Key / String / Type / EndevirFinder のいずれかを指定してください',
        ),
    };
  }

  /// [root]以下を検索してマッチする要素を返す。
  List<Element> resolve(Element root) {
    final matches = <Element>[];
    void visit(Element element) {
      if (this.matches(element)) matches.add(element);
      element.visitChildren(visit);
    }

    visit(root);
    return matches;
  }

  /// この要素がマッチするか。
  bool matches(Element element);

  /// 人間可読な説明（証跡・エラーメッセージに使う）。
  String describe();

  static String _symbolName(Symbol symbol) {
    // dart:mirrorsなしでSymbol名を取り出す（'Symbol("name")' 形式から抽出）
    final raw = symbol.toString();
    return raw.substring('Symbol("'.length, raw.length - '")'.length);
  }
}

/// ウィジェットキーによるファインダー。
class KeyFinder extends EndevirFinder {
  const KeyFinder(this.key);

  final Key key;

  @override
  bool matches(Element element) => element.widget.key == key;

  @override
  String describe() => 'key: $key';
}

/// Textウィジェットの部分一致ファインダー。
class TextFinder extends EndevirFinder {
  const TextFinder(this.text);

  final String text;

  @override
  bool matches(Element element) {
    final widget = element.widget;
    return widget is Text && (widget.data?.contains(text) ?? false);
  }

  @override
  String describe() => 'text: "$text"';
}

/// ウィジェット型によるファインダー。
class TypeFinder extends EndevirFinder {
  const TypeFinder(this.type);

  final Type type;

  @override
  bool matches(Element element) => element.widget.runtimeType == type;

  @override
  String describe() => 'type: $type';
}
