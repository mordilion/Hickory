import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../locale/locale_store.dart';

part 'locale_provider.g.dart';

@Riverpod(keepAlive: true)
Future<LocaleStore> localeStore(Ref ref) async =>
    LocaleStore(supportDirectory: await getApplicationSupportDirectory());

/// The user's explicit language choice; `null` means "follow the system
/// locale". Per device by design — deliberately NOT part of the synced
/// app_settings entity (devices may run different OS languages).
@Riverpod(keepAlive: true)
class LocaleController extends _$LocaleController {
  @override
  Future<Locale?> build() async {
    final store = await ref.watch(localeStoreProvider.future);
    final code = await store.read();
    return code == null ? null : Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    // State first: the choice applies to the running session even when
    // persisting fails (spec's error-handling rule).
    state = AsyncData(locale);
    try {
      final store = await ref.read(localeStoreProvider.future);
      if (locale == null) {
        await store.clear();
      } else {
        await store.write(locale.languageCode);
      }
    } catch (error) {
      debugPrint('Failed to persist locale preference: $error');
    }
  }
}
