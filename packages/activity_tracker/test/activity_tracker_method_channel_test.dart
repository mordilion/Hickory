import 'package:activity_tracker/activity_tracker_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelActivityTracker();
  final channel = platform.methodChannel;

  final log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (methodCall) async {
        log.add(methodCall);
        return switch (methodCall.method) {
          'getIdleSeconds' => 17,
          'hasPermissions' => true,
          'requestPermissions' => true,
          _ => null,
        };
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    log.clear();
  });

  test('getIdleSeconds calls the native method and returns its value', () async {
    expect(await platform.getIdleSeconds(), 17);
    expect(log, [isMethodCall('getIdleSeconds', arguments: null)]);
  });

  test('hasPermissions calls the native method and returns its value', () async {
    expect(await platform.hasPermissions(), isTrue);
    expect(log, [isMethodCall('hasPermissions', arguments: null)]);
  });

  test('requestPermissions calls the native method and returns its value', () async {
    expect(await platform.requestPermissions(), isTrue);
    expect(log, [isMethodCall('requestPermissions', arguments: null)]);
  });
}
