import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

/// Endevir M0スパイクの検証対象アプリ。
/// 各画面は待機戦略（CORE-102）の検証シナリオに対応する:
/// - DelayedLoadScreen: 非同期ロード完了の検知
/// - AnimationScreen: 有限アニメーションの終了検知
/// - InfiniteAnimationScreen: 無限アニメーション下での安定判定（pumpAndSettleキラー）
/// - FormScreen: 基本操作（入力・タップ）とバリデーション表示
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Endevir Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Endevir Example')),
      body: ListView(
        children: [
          _NavTile(
            key: const Key('nav_delayed_load'),
            title: '遅延ロード',
            builder: (_) => const DelayedLoadScreen(),
          ),
          _NavTile(
            key: const Key('nav_animation'),
            title: 'アニメーション',
            builder: (_) => const AnimationScreen(),
          ),
          _NavTile(
            key: const Key('nav_infinite_animation'),
            title: '無限アニメーション',
            builder: (_) => const InfiniteAnimationScreen(),
          ),
          _NavTile(
            key: const Key('nav_form'),
            title: 'フォーム',
            builder: (_) => const FormScreen(),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({super.key, required this.title, required this.builder});

  final String title;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: builder)),
    );
  }
}

/// 指定時間後にコンテンツが表示される画面。
/// 待機戦略が「ローディング終了」をsleepなしで検知できるかの検証対象。
class DelayedLoadScreen extends StatefulWidget {
  const DelayedLoadScreen({super.key, this.delay = const Duration(seconds: 3)});

  final Duration delay;

  @override
  State<DelayedLoadScreen> createState() => _DelayedLoadScreenState();
}

class _DelayedLoadScreenState extends State<DelayedLoadScreen> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('遅延ロード')),
      body: Center(
        child: _loaded
            ? const Text('読み込み完了', key: Key('loaded_content'))
            : const CircularProgressIndicator(key: Key('loading_indicator')),
      ),
    );
  }
}

/// タップで有限アニメーションが走る画面。
/// アニメーション中の操作抑制と終了検知の検証対象。
class AnimationScreen extends StatefulWidget {
  const AnimationScreen({super.key});

  @override
  State<AnimationScreen> createState() => _AnimationScreenState();
}

class _AnimationScreenState extends State<AnimationScreen> {
  bool _expanded = false;
  int _completedCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アニメーション')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              key: const Key('animated_box'),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              width: _expanded ? 240 : 80,
              height: _expanded ? 240 : 80,
              color: Colors.indigo,
              onEnd: () => setState(() => _completedCount++),
            ),
            const SizedBox(height: 24),
            Text(
              'アニメーション完了: $_completedCount回',
              key: const Key('animation_count'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('toggle_button'),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: const Text('切り替え'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 常時スピナーが回り続ける画面（pumpAndSettleはタイムアウトする）。
/// 無限アニメーション下での操作・検証の安定性の検証対象。
class InfiniteAnimationScreen extends StatefulWidget {
  const InfiniteAnimationScreen({super.key});

  @override
  State<InfiniteAnimationScreen> createState() =>
      _InfiniteAnimationScreenState();
}

class _InfiniteAnimationScreenState extends State<InfiniteAnimationScreen> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('無限アニメーション')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(key: Key('infinite_spinner')),
            const SizedBox(height: 24),
            Text('カウント: $_count', key: const Key('counter_text')),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('increment_button'),
              onPressed: () => setState(() => _count++),
              child: const Text('カウントアップ'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 入力・バリデーション・擬似遅延つき送信を持つフォーム画面。
/// 基本操作（enterText/tap）と結果表示の検証対象。
class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _submitted = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('フォーム')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                key: const Key('email_field'),
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'メールアドレス'),
                validator: (value) => (value == null || !value.contains('@'))
                    ? 'メールアドレスが不正です'
                    : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('submit_button'),
                onPressed: _submit,
                child: const Text('送信'),
              ),
              const SizedBox(height: 24),
              if (_submitted) const Text('送信しました', key: Key('submit_result')),
            ],
          ),
        ),
      ),
    );
  }
}
