// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry_tree_expansion.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which nodes of the entries hierarchy are expanded, as keys from
/// [yearTreeKey] and friends.
///
/// Kept alive so switching tabs doesn't collapse the list, and deliberately
/// not persisted: every app start reopens the path to today (see
/// docs/superpowers/specs/2026-08-18-entries-hierarchy-design.md). The seed is
/// computed once on first read, so an app left running past midnight keeps
/// yesterday's path until it restarts.

@ProviderFor(EntryTreeExpansion)
final entryTreeExpansionProvider = EntryTreeExpansionProvider._();

/// Which nodes of the entries hierarchy are expanded, as keys from
/// [yearTreeKey] and friends.
///
/// Kept alive so switching tabs doesn't collapse the list, and deliberately
/// not persisted: every app start reopens the path to today (see
/// docs/superpowers/specs/2026-08-18-entries-hierarchy-design.md). The seed is
/// computed once on first read, so an app left running past midnight keeps
/// yesterday's path until it restarts.
final class EntryTreeExpansionProvider
    extends $NotifierProvider<EntryTreeExpansion, Set<String>> {
  /// Which nodes of the entries hierarchy are expanded, as keys from
  /// [yearTreeKey] and friends.
  ///
  /// Kept alive so switching tabs doesn't collapse the list, and deliberately
  /// not persisted: every app start reopens the path to today (see
  /// docs/superpowers/specs/2026-08-18-entries-hierarchy-design.md). The seed is
  /// computed once on first read, so an app left running past midnight keeps
  /// yesterday's path until it restarts.
  EntryTreeExpansionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'entryTreeExpansionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$entryTreeExpansionHash();

  @$internal
  @override
  EntryTreeExpansion create() => EntryTreeExpansion();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$entryTreeExpansionHash() =>
    r'10be32d23eb3ef421455e64db5cb3141451c6baa';

/// Which nodes of the entries hierarchy are expanded, as keys from
/// [yearTreeKey] and friends.
///
/// Kept alive so switching tabs doesn't collapse the list, and deliberately
/// not persisted: every app start reopens the path to today (see
/// docs/superpowers/specs/2026-08-18-entries-hierarchy-design.md). The seed is
/// computed once on first read, so an app left running past midnight keeps
/// yesterday's path until it restarts.

abstract class _$EntryTreeExpansion extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
