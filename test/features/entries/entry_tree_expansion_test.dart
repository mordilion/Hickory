import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/entries/entry_tree.dart';
import 'package:hickory/features/entries/entry_tree_expansion.dart';

void main() {
  test('starts expanded on the path to today', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(entryTreeExpansionProvider),
      defaultExpandedKeys(DateTime.now()),
    );
  });

  test('toggle adds a collapsed key and removes an expanded one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(entryTreeExpansionProvider.notifier);

    notifier.toggle(yearTreeKey(2020));
    expect(
      container.read(entryTreeExpansionProvider),
      contains(yearTreeKey(2020)),
    );

    notifier.toggle(yearTreeKey(2020));
    expect(
      container.read(entryTreeExpansionProvider),
      isNot(contains(yearTreeKey(2020))),
    );
  });
}
