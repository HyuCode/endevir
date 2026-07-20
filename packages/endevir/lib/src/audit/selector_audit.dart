import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoSwitch;
import 'package:flutter/material.dart'
    show
        ButtonStyleButton,
        Checkbox,
        FloatingActionButton,
        IconButton,
        Slider,
        Switch,
        SwitchListTile,
        TextField;
import 'package:flutter/widgets.dart';

/// 安定セレクタ契約の監査重大度。
enum SelectorAuditSeverity { warning, error }

/// 安定セレクタ契約に対する個別の指摘。
class SelectorAuditIssue {
  const SelectorAuditIssue({
    required this.code,
    required this.severity,
    required this.message,
    required this.path,
  });

  final String code;
  final SelectorAuditSeverity severity;
  final String message;
  final String path;

  @override
  String toString() => '[${severity.name}] $code: $message ($path)';
}

/// Widgetツリーの安定セレクタ監査結果。
class SelectorAuditReport {
  const SelectorAuditReport(this.issues);

  final List<SelectorAuditIssue> issues;

  int get errorCount => issues
      .where((issue) => issue.severity == SelectorAuditSeverity.error)
      .length;

  int get warningCount => issues
      .where((issue) => issue.severity == SelectorAuditSeverity.warning)
      .length;

  bool get isClean => issues.isEmpty;

  bool passes({bool warningsAsErrors = false}) =>
      errorCount == 0 && (!warningsAsErrors || warningCount == 0);

  String format() {
    final summary =
        'selector audit: ${passes() ? 'PASS' : 'FAIL'} '
        '(errors: $errorCount, warnings: $warningCount)';
    if (issues.isEmpty) return summary;
    return '$summary\n${issues.map((issue) => issue.toString()).join('\n')}';
  }
}

/// [SelectorAuditReport]が要求する品質ゲートを満たさない。
class SelectorAuditException implements Exception {
  const SelectorAuditException(this.report, {required this.warningsAsErrors});

  final SelectorAuditReport report;
  final bool warningsAsErrors;

  @override
  String toString() => 'SelectorAuditException: ${report.format()}';
}

/// 現在のWidgetツリーから安定セレクタ契約を監査する。
///
/// 重複は単一要素操作を曖昧にするためerror。操作要素の識別子欠落と
/// `container: false`のSemantics identifierは、内側のSemanticsとマージされ
/// 外部UIツリーから消える可能性があるためwarningとする。
class SelectorAuditor {
  const SelectorAuditor();

  SelectorAuditReport audit(Element root) {
    final issues = <SelectorAuditIssue>[];
    final keys = <String, List<String>>{};
    final identifiers = <String, List<String>>{};

    void visit(Element element, String? inheritedIdentifier) {
      final widget = element.widget;
      if (widget case final Offstage offstage when offstage.offstage) return;
      if (widget case final Visibility visibility when !visibility.visible) {
        return;
      }
      final path = _elementPath(element);
      final key = _stableKey(widget.key);
      if (key != null) {
        keys.putIfAbsent(key, () => <String>[]).add(path);
      }

      var effectiveIdentifier = inheritedIdentifier;
      if (widget case final Semantics semantics) {
        final identifier = semantics.properties.identifier;
        if (identifier != null && identifier.isNotEmpty) {
          effectiveIdentifier = identifier;
          identifiers.putIfAbsent(identifier, () => <String>[]).add(path);
          if (!semantics.container) {
            issues.add(
              SelectorAuditIssue(
                code: 'uncontained-semantics-identifier',
                severity: SelectorAuditSeverity.warning,
                message:
                    'Semantics.identifier "$identifier" may merge into a '
                    'descendant node; set container: true for an external selector',
                path: path,
              ),
            );
          }
        }
      }

      if (_isInteractive(widget) &&
          key == null &&
          effectiveIdentifier == null) {
        issues.add(
          SelectorAuditIssue(
            code: 'missing-stable-selector',
            severity: SelectorAuditSeverity.warning,
            message:
                '${widget.runtimeType} has neither ValueKey<String> nor an '
                'ancestor Semantics.identifier',
            path: path,
          ),
        );
      }

      element.visitChildren((child) => visit(child, effectiveIdentifier));
    }

    visit(root, null);
    _addDuplicates(
      issues,
      values: keys,
      code: 'duplicate-key',
      label: 'ValueKey<String>',
    );
    _addDuplicates(
      issues,
      values: identifiers,
      code: 'duplicate-semantics-identifier',
      label: 'Semantics.identifier',
    );

    return SelectorAuditReport(List.unmodifiable(issues));
  }

  static void _addDuplicates(
    List<SelectorAuditIssue> issues, {
    required Map<String, List<String>> values,
    required String code,
    required String label,
  }) {
    for (final MapEntry(key: value, value: paths) in values.entries) {
      if (paths.length < 2) continue;
      issues.add(
        SelectorAuditIssue(
          code: code,
          severity: SelectorAuditSeverity.error,
          message: '$label "$value" is used ${paths.length} times',
          path: paths.join(' | '),
        ),
      );
    }
  }

  static String? _stableKey(Key? key) =>
      key is ValueKey<String> && key.value.isNotEmpty ? key.value : null;

  static bool _isInteractive(Widget widget) {
    // Material/Cupertinoが内部で生成するprivate widgetは利用者が
    // KeyやSemanticsを付与できないため監査対象にしない。
    if (widget.runtimeType.toString().startsWith('_')) return false;
    return widget is ButtonStyleButton ||
        widget is CupertinoButton ||
        widget is FloatingActionButton ||
        widget is IconButton ||
        widget is TextField ||
        widget is Checkbox ||
        widget is Switch ||
        widget is CupertinoSwitch ||
        widget is SwitchListTile ||
        widget is Slider;
  }

  static String _elementPath(Element element) {
    final segments = <String>[_segment(element)];
    element.visitAncestorElements((ancestor) {
      segments.add(_segment(ancestor));
      return segments.length < 8;
    });
    return segments.reversed.join(' > ');
  }

  static String _segment(Element element) {
    final key = _stableKey(element.widget.key);
    return '${element.widget.runtimeType}${key == null ? '' : '[$key]'}';
  }
}
