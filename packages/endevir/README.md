# Endevir

Endevir is a Flutter E2E testing framework focused on reliable automatic waits,
fast reruns, and reviewable execution evidence.

> Endevir is preparing for its first alpha release. APIs may change before the
> stable release.

## Features

- Event-driven waits with actionability and position-stability checks
- Lazy finders for keys, text, regular expressions, widget types, semantics,
  and descendant scopes
- Named steps with screenshots and correlated Dart logs
- Per-test retries and configurable timeouts
- The same test bundle runs on iOS and Android

## Getting started

Add the test API and CLI to a Flutter application:

```console
flutter pub add endevir
flutter pub add --dev endevir_cli
dart run endevir_cli:endevir_cli init
```

Until the packages are published, clone the Endevir repository and run:

```console
dart run endevir_cli:endevir_cli init --endevir-path /path/to/endevir
```

The initializer creates `endevir_test/main_test.dart`, a smoke test, and
`endevir.yaml` without overwriting existing files.

## Writing a test

```dart
import 'package:endevir/endevir.dart';

void main() {
  endevirTest(
    'signs in',
    (e) async {
      await e.step('Enter credentials', () async {
        await e.$(#emailField).enterText('dev@example.com');
        await e.$(#submitButton).tap();
      });
      await e.expectVisible('Welcome');
    },
    mode: EndevirTestMode.userPath,
  );
}
```

Tests default to `EndevirTestMode.inProcess`, which permits direct access to
application state, services, and callbacks. Mark a test as `userPath` only when
the scenario advances exclusively through public UI operations. Both modes
currently run inside the Flutter application process; `userPath` is not an
external black-box driver and does not support system UI such as permission
dialogs or share sheets.

Register test files through the generated bundle in
`endevir_test/main_test.dart`, then execute them on a simulator or emulator:

```console
dart run endevir_cli:endevir_cli test -p ios -d <simulator-udid>
dart run endevir_cli:endevir_cli test -p android -d <adb-serial>
```

Each run writes `.endevir/trace.jsonl` and a self-contained
`.endevir/report.html` evidence report.

## Stable selectors

Use `ValueKey<String>` for Endevir-only widget-tree selectors. Use
`Semantics.identifier` when the same contract must also be visible to external
accessibility-based runners such as Maestro:

```dart
Semantics(
  container: true,
  identifier: 'counter.increment',
  child: IconButton(
    key: const ValueKey('increment'),
    onPressed: increment,
    icon: const Icon(Icons.add),
  ),
)
```

Both contracts can be selected explicitly:

```dart
await e.$(#increment).tap();
await e.$(
  EndevirFinder.semanticsIdentifier('counter.increment'),
).tap();
```

Audit the visible widget tree to catch ambiguous or unstable selectors:

```dart
final report = e.auditSelectors();
print(report.format());

// Duplicate keys and identifiers always fail. In strict mode, missing stable
// selectors and identifiers without `container: true` fail as well.
e.expectSelectorsClean(warningsAsErrors: true);
```

The audit ignores hidden `Offstage` and `Visibility` subtrees so routes can
reuse local selector names without creating false duplicate errors.

## Status and support

The supported toolchain is Flutter 3.41 or newer with Dart 3.11 or newer.
File bugs and feature requests in the
[Endevir issue tracker](https://github.com/HyuCode/endevir/issues).
