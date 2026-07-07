// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_id_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Generated once per install and persisted to a plain file (not synced) so
/// it survives app restarts; identifies which device wrote which sync
/// event-log entries down the line.

@ProviderFor(deviceId)
final deviceIdProvider = DeviceIdProvider._();

/// Generated once per install and persisted to a plain file (not synced) so
/// it survives app restarts; identifies which device wrote which sync
/// event-log entries down the line.

final class DeviceIdProvider
    extends $FunctionalProvider<AsyncValue<String>, String, FutureOr<String>>
    with $FutureModifier<String>, $FutureProvider<String> {
  /// Generated once per install and persisted to a plain file (not synced) so
  /// it survives app restarts; identifies which device wrote which sync
  /// event-log entries down the line.
  DeviceIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceIdHash();

  @$internal
  @override
  $FutureProviderElement<String> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String> create(Ref ref) {
    return deviceId(ref);
  }
}

String _$deviceIdHash() => r'8b93fda7b7ff94c43108d7cdf374a411f0fa717f';
