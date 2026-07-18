import 'dart:convert';
import 'dart:io';

import 'package:endevir_cli/src/device_preflight.dart';
import 'package:test/test.dart';

void main() {
  ProcessResult result(int exitCode, String stdout, [String stderr = '']) =>
      ProcessResult(1, exitCode, stdout, stderr);

  group('iOS device preflight', () {
    test('Bootedのシミュレータを受け入れる', () async {
      final output = jsonEncode({
        'devices': {
          'com.apple.CoreSimulator.SimRuntime.iOS-18-5': [
            {
              'udid': 'SIM-1',
              'name': 'iPhone 16',
              'state': 'Booted',
              'dataPath': '/tmp/sim-1',
            },
          ],
        },
      });

      await preflightDevice(
        platform: 'ios',
        device: 'SIM-1',
        commandRunner: (executable, _) async => executable == 'xcrun'
            ? result(0, output)
            : result(0, 'Filesystem 1024-blocks Used Available Capacity Mounted\n'
                '/dev/disk 10000000 1000 9999000 1% /tmp\n'),
      );
    });

    test('存在しないUDIDをnotFoundとして報告する', () async {
      await expectLater(
        preflightDevice(
          platform: 'ios',
          device: 'MISSING',
          commandRunner: (_, _) async => result(0, jsonEncode({'devices': {}})),
        ),
        throwsA(
          isA<DevicePreflightException>().having(
            (error) => error.failure,
            'failure',
            DevicePreflightFailure.notFound,
          ),
        ),
      );
    });

    test('ShutdownのシミュレータをnotReadyとして報告する', () async {
      final output = jsonEncode({
        'devices': {
          'runtime': [
            {'udid': 'SIM-1', 'state': 'Shutdown'},
          ],
        },
      });

      await expectLater(
        preflightDevice(
          platform: 'ios',
          device: 'SIM-1',
          commandRunner: (_, _) async => result(0, output),
        ),
        throwsA(
          isA<DevicePreflightException>().having(
            (error) => error.failure,
            'failure',
            DevicePreflightFailure.notReady,
          ),
        ),
      );
    });

    test('空き容量不足をinsufficientSpaceとして報告する', () async {
      final output = jsonEncode({
        'devices': {
          'runtime': [
            {
              'udid': 'SIM-1',
              'state': 'Booted',
              'dataPath': '/tmp/sim-1',
            },
          ],
        },
      });

      await expectLater(
        preflightDevice(
          platform: 'ios',
          device: 'SIM-1',
          minimumFreeBytes: 1024 * 1024,
          commandRunner: (executable, _) async => executable == 'xcrun'
              ? result(0, output)
              : result(0,
                  'Filesystem 1024-blocks Used Available Capacity Mounted\n'
                  '/dev/disk 10000 9500 500 95% /tmp\n'),
        ),
        throwsA(
          isA<DevicePreflightException>().having(
            (error) => error.failure,
            'failure',
            DevicePreflightFailure.insufficientSpace,
          ),
        ),
      );
    });
  });

  group('Android device preflight', () {
    test('device状態を受け入れ、対象serialを指定する', () async {
      final calls = <List<String>>[];
      await preflightDevice(
        platform: 'android',
        device: 'emulator-5554',
        commandRunner: (_, args) async {
          calls.add(args);
          return args.last == 'get-state'
              ? result(0, 'device\n')
              : result(0,
                  'Filesystem 1024-blocks Used Available Capacity Mounted\n'
                  '/dev/block 10000000 1000 9999000 1% /data\n');
        },
      );

      expect(calls, [
        ['-s', 'emulator-5554', 'get-state'],
        ['-s', 'emulator-5554', 'shell', 'df', '-Pk', '/data'],
      ]);
    });

    test('offlineをnotReadyとして報告する', () async {
      await expectLater(
        preflightDevice(
          platform: 'android',
          device: 'emulator-5554',
          commandRunner: (_, _) async => result(1, '', 'error: device offline'),
        ),
        throwsA(
          isA<DevicePreflightException>().having(
            (error) => error.failure,
            'failure',
            DevicePreflightFailure.notReady,
          ),
        ),
      );
    });

    test('未知のserialをnotFoundとして報告する', () async {
      await expectLater(
        preflightDevice(
          platform: 'android',
          device: 'missing',
          commandRunner: (_, _) async =>
              result(1, '', 'error: device not found'),
        ),
        throwsA(
          isA<DevicePreflightException>().having(
            (error) => error.failure,
            'failure',
            DevicePreflightFailure.notFound,
          ),
        ),
      );
    });

    test('解析できないdf出力をcommandFailedとして報告する', () async {
      await expectLater(
        preflightDevice(
          platform: 'android',
          device: 'emulator-5554',
          commandRunner: (_, args) async => args.last == 'get-state'
              ? result(0, 'device\n')
              : result(0, 'unexpected output'),
        ),
        throwsA(
          isA<DevicePreflightException>().having(
            (error) => error.failure,
            'failure',
            DevicePreflightFailure.commandFailed,
          ),
        ),
      );
    });
  });
}
