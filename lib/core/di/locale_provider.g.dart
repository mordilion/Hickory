// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'locale_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(localeStore)
final localeStoreProvider = LocaleStoreProvider._();

final class LocaleStoreProvider
    extends
        $FunctionalProvider<
          AsyncValue<LocaleStore>,
          LocaleStore,
          FutureOr<LocaleStore>
        >
    with $FutureModifier<LocaleStore>, $FutureProvider<LocaleStore> {
  LocaleStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localeStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localeStoreHash();

  @$internal
  @override
  $FutureProviderElement<LocaleStore> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LocaleStore> create(Ref ref) {
    return localeStore(ref);
  }
}

String _$localeStoreHash() => r'1741c023c0fc7af64c71f1159c118e32877c2590';

/// The user's explicit language choice; `null` means "follow the system
/// locale". Per device by design — deliberately NOT part of the synced
/// app_settings entity (devices may run different OS languages).

@ProviderFor(LocaleController)
final localeControllerProvider = LocaleControllerProvider._();

/// The user's explicit language choice; `null` means "follow the system
/// locale". Per device by design — deliberately NOT part of the synced
/// app_settings entity (devices may run different OS languages).
final class LocaleControllerProvider
    extends $AsyncNotifierProvider<LocaleController, Locale?> {
  /// The user's explicit language choice; `null` means "follow the system
  /// locale". Per device by design — deliberately NOT part of the synced
  /// app_settings entity (devices may run different OS languages).
  LocaleControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localeControllerHash();

  @$internal
  @override
  LocaleController create() => LocaleController();
}

String _$localeControllerHash() => r'9dbb0ec5788a1ee1d5b047648d9c84adb059a2fb';

/// The user's explicit language choice; `null` means "follow the system
/// locale". Per device by design — deliberately NOT part of the synced
/// app_settings entity (devices may run different OS languages).

abstract class _$LocaleController extends $AsyncNotifier<Locale?> {
  FutureOr<Locale?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Locale?>, Locale?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Locale?>, Locale?>,
              AsyncValue<Locale?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
