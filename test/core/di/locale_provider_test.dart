import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/locale_provider.dart';
import 'package:hickory/core/locale/locale_store.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('locale_provider_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          localeStoreProvider.overrideWith(
            (ref) async => LocaleStore(supportDirectory: tempDir),
          ),
        ],
      );

  test('starts as null (follow system) when nothing is stored', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    expect(await container.read(localeControllerProvider.future), isNull);
  });

  test('setLocale updates state and persists across containers', () async {
    final first = makeContainer();
    await first.read(localeControllerProvider.future);
    await first.read(localeControllerProvider.notifier).setLocale(const Locale('nl'));
    expect(first.read(localeControllerProvider).value, const Locale('nl'));
    first.dispose();

    final second = makeContainer();
    addTearDown(second.dispose);
    expect(await second.read(localeControllerProvider.future), const Locale('nl'));
  });

  test('setLocale(null) reverts to following the system', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(localeControllerProvider.future);
    final controller = container.read(localeControllerProvider.notifier);
    await controller.setLocale(const Locale('es'));
    await controller.setLocale(null);
    expect(container.read(localeControllerProvider).value, isNull);
    expect(await LocaleStore(supportDirectory: tempDir).read(), isNull);
  });
}
