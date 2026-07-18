# Endevir CLI

The command-line interface for setting up, diagnosing, running, and rapidly
rerunning Endevir E2E tests in Flutter applications.

> Endevir is preparing for its first alpha release. Commands and options may
> change before the stable release.

## Commands

| Command                  | Purpose                                                     |
| ------------------------ | ----------------------------------------------------------- |
| `endevir init`           | Add an idempotent test scaffold and configuration           |
| `endevir doctor`         | Diagnose the Flutter, Android, iOS, and project environment |
| `endevir test`           | Build, launch, run tests, and collect the evidence trace    |
| `endevir develop`        | Watch test files and rerun through Flutter hot restart      |
| `endevir native android` | Generate or run the Android instrumentation test mapping    |

## Installation

After the first alpha is published:

```console
dart pub global activate endevir_cli
endevir doctor
```

From a source checkout, invoke the executable through Dart:

```console
dart run endevir_cli:endevir_cli doctor
```

## Quick start

Run these commands from a Flutter application root:

```console
endevir init
endevir doctor
endevir test -p ios -d <simulator-udid>
```

For Android, pass an adb serial instead:

```console
endevir test -p android -d <adb-serial>
```

Use `endevir <command> --help` for command-specific options. Test output,
traces, screenshots, and the self-contained HTML report are stored in
`.endevir/` by default.

## Android device farms

Generate the instrumentation runner and build the app/test APK pair with:

```console
endevir native android --build
```

The generated APK pair has been verified with Firebase Test Lab. See the
[benchmark record](https://github.com/HyuCode/endevir/blob/main/docs/03-benchmarks/01-mvp-benchmarks.md)
for the tested environment.
