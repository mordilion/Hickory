// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entries_location.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The list's current location. Kept alive so switching tabs doesn't send you
/// back to the start, and deliberately not persisted: every app start reopens
/// the current week. Null means "not navigated yet", which the list resolves
/// through [initialLocation] once it knows what data exists.

@ProviderFor(EntriesLocationController)
final entriesLocationControllerProvider = EntriesLocationControllerProvider._();

/// The list's current location. Kept alive so switching tabs doesn't send you
/// back to the start, and deliberately not persisted: every app start reopens
/// the current week. Null means "not navigated yet", which the list resolves
/// through [initialLocation] once it knows what data exists.
final class EntriesLocationControllerProvider
    extends $NotifierProvider<EntriesLocationController, EntriesLocation?> {
  /// The list's current location. Kept alive so switching tabs doesn't send you
  /// back to the start, and deliberately not persisted: every app start reopens
  /// the current week. Null means "not navigated yet", which the list resolves
  /// through [initialLocation] once it knows what data exists.
  EntriesLocationControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'entriesLocationControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$entriesLocationControllerHash();

  @$internal
  @override
  EntriesLocationController create() => EntriesLocationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EntriesLocation? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EntriesLocation?>(value),
    );
  }
}

String _$entriesLocationControllerHash() =>
    r'b17e1f48039541b43d77137efe72103e54df61b2';

/// The list's current location. Kept alive so switching tabs doesn't send you
/// back to the start, and deliberately not persisted: every app start reopens
/// the current week. Null means "not navigated yet", which the list resolves
/// through [initialLocation] once it knows what data exists.

abstract class _$EntriesLocationController extends $Notifier<EntriesLocation?> {
  EntriesLocation? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EntriesLocation?, EntriesLocation?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EntriesLocation?, EntriesLocation?>,
              EntriesLocation?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
