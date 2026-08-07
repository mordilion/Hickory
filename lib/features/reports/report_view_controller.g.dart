// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report_view_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reportViewStateStore)
final reportViewStateStoreProvider = ReportViewStateStoreProvider._();

final class ReportViewStateStoreProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReportViewStateStore>,
          ReportViewStateStore,
          FutureOr<ReportViewStateStore>
        >
    with
        $FutureModifier<ReportViewStateStore>,
        $FutureProvider<ReportViewStateStore> {
  ReportViewStateStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reportViewStateStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reportViewStateStoreHash();

  @$internal
  @override
  $FutureProviderElement<ReportViewStateStore> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ReportViewStateStore> create(Ref ref) {
    return reportViewStateStore(ref);
  }
}

String _$reportViewStateStoreHash() =>
    r'b4311fdd62e631518bd27494d6ab6083f67727c3';

/// The Reports screen's remembered range + filters (see [ReportViewState]).
/// Loaded once from disk on first use and kept alive for the app's
/// lifetime -- same pattern as LocaleController.

@ProviderFor(ReportViewController)
final reportViewControllerProvider = ReportViewControllerProvider._();

/// The Reports screen's remembered range + filters (see [ReportViewState]).
/// Loaded once from disk on first use and kept alive for the app's
/// lifetime -- same pattern as LocaleController.
final class ReportViewControllerProvider
    extends $AsyncNotifierProvider<ReportViewController, ReportViewState> {
  /// The Reports screen's remembered range + filters (see [ReportViewState]).
  /// Loaded once from disk on first use and kept alive for the app's
  /// lifetime -- same pattern as LocaleController.
  ReportViewControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reportViewControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reportViewControllerHash();

  @$internal
  @override
  ReportViewController create() => ReportViewController();
}

String _$reportViewControllerHash() =>
    r'dbed9f4cf5dd23e99b2d026bd65e72c215318824';

/// The Reports screen's remembered range + filters (see [ReportViewState]).
/// Loaded once from disk on first use and kept alive for the app's
/// lifetime -- same pattern as LocaleController.

abstract class _$ReportViewController extends $AsyncNotifier<ReportViewState> {
  FutureOr<ReportViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ReportViewState>, ReportViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReportViewState>, ReportViewState>,
              AsyncValue<ReportViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
