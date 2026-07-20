import 'package:endevir/src/audit/selector_audit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SelectorAuditReport audit(WidgetTester tester) =>
      const SelectorAuditor().audit(tester.binding.rootElement!);

  testWidgets('stable selectors pass without issues', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              IconButton(
                key: const ValueKey('increment'),
                onPressed: () {},
                icon: const Icon(Icons.add),
              ),
              Semantics(
                container: true,
                identifier: 'counter.name',
                child: const TextField(),
              ),
            ],
          ),
        ),
      ),
    );

    expect(audit(tester).issues, isEmpty);
  });

  testWidgets('duplicate keys and identifiers are errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const Column(children: [Text('one', key: ValueKey('duplicate'))]),
            const Row(children: [Text('two', key: ValueKey('duplicate'))]),
            Semantics(
              container: true,
              identifier: 'duplicate.id',
              child: const Text('three'),
            ),
            Semantics(
              container: true,
              identifier: 'duplicate.id',
              child: const Text('four'),
            ),
          ],
        ),
      ),
    );

    final report = audit(tester);
    expect(report.errorCount, 2);
    expect(report.issues.map((issue) => issue.code), contains('duplicate-key'));
    expect(
      report.issues.map((issue) => issue.code),
      contains('duplicate-semantics-identifier'),
    );
    expect(report.passes(), isFalse);
  });

  testWidgets('interactive widgets without a stable selector are warnings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
      ),
    );

    final report = audit(tester);
    expect(report.warningCount, greaterThanOrEqualTo(1));
    expect(
      report.issues.map((issue) => issue.code),
      contains('missing-stable-selector'),
    );
    expect(report.passes(), isTrue);
    expect(report.passes(warningsAsErrors: true), isFalse);
  });

  testWidgets('identifier without a semantics container is warned', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Semantics(
          identifier: 'counter.increment',
          child: IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
        ),
      ),
    );

    final report = audit(tester);
    expect(
      report.issues.map((issue) => issue.code),
      contains('uncontained-semantics-identifier'),
    );
    expect(
      report.issues.map((issue) => issue.code),
      isNot(contains('missing-stable-selector')),
    );
  });

  testWidgets('offstage routes do not create false duplicate errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            Text('current', key: ValueKey('save')),
            Offstage(
              offstage: true,
              child: Text('previous', key: ValueKey('save')),
            ),
          ],
        ),
      ),
    );

    expect(audit(tester).errorCount, 0);
  });
}
