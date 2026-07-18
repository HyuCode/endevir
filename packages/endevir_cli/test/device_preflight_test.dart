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
            {'udid': 'SIM-1', 'name': 'iPhone 16', 'state': 'Booted'},
          ],
        },
      });

      await preflightDevice(
        platform: 'ios',
        device: 'SIM-1',
        commandRunner: (_, _) async => result(0, output),
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
  });

  group('Android device preflight', () {
    test('device状態を受け入れ、対象serialを指定する', () async {
      late List<String> arguments;
      await preflightDevice(
        platform: 'android',
        device: 'emulator-5554',
        commandRunner: (_, args) async {
          arguments = args;
          return result(0, 'device\n');
        },
      );

      expect(arguments, ['-s', 'emulator-5554', 'get-state']);
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
  });
}
