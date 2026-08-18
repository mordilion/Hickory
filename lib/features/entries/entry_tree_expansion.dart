import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'entry_tree.dart';

part 'entry_tree_expansion.g.dart';

/// Which nodes of the entries hierarchy are expanded, as keys from
/// [yearTreeKey] and friends.
///
/// Kept alive so switching tabs doesn't collapse the list, and deliberately
/// not persisted: every app start reopens the path to today (see
/// docs/superpowers/specs/2026-08-18-entries-hierarchy-design.md). The seed is
/// computed once on first read, so an app left running past midnight keeps
/// yesterday's path until it restarts.
@Riverpod(keepAlive: true)
class EntryTreeExpansion extends _$EntryTreeExpansion {
  @override
  Set<String> build() => defaultExpandedKeys(DateTime.now());

  /// Expands [key] when collapsed and collapses it when expanded. Keys of
  /// nodes that have since disappeared are harmless -- the set is only ever
  /// queried, never iterated.
  void toggle(String key) {
    final next = {...state};
    if (!next.remove(key)) next.add(key);
    state = next;
  }
}
