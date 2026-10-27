import 'package:flutter/material.dart';

/// A generic bottom-navigation container: index state, an IndexedStack of
/// [children], a NavigationBar built from [destinations], and an optional
/// per-tab floating action button via [fabBuilder]. Has no Riverpod (or any
/// other app-specific) dependency on purpose — see AppShell for the real
/// wiring, and Task 10 in the implementation plan for why that split
/// exists (keeps this widget cheaply testable with dummy children).
///
/// Works uncontrolled by default (it owns the selected index, starting at
/// [initialIndex]) or controlled, by passing [selectedIndex] together with
/// [onDestinationSelected] — needed when something outside the bar has to
/// switch tabs, such as the startup update prompt jumping to Settings.
class NavShell extends StatefulWidget {
  const NavShell({
    super.key,
    required this.children,
    required this.destinations,
    this.initialIndex = 0,
    this.fabBuilder,
    this.selectedIndex,
    this.onDestinationSelected,
  }) : assert(children.length == destinations.length),
       assert(
         (selectedIndex == null) == (onDestinationSelected == null),
         'Controlled mode needs both selectedIndex and onDestinationSelected: '
         'with only one of them the bar and its owner drift apart.',
       );

  final List<Widget> children;
  final List<NavigationDestination> destinations;

  /// Only used when uncontrolled; ignored once [selectedIndex] is given.
  final int initialIndex;
  final Widget? Function(int selectedIndex)? fabBuilder;

  /// Non-null puts the widget in controlled mode: the caller owns the index
  /// and this widget never changes tabs by itself.
  final int? selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  late int _ownIndex = widget.initialIndex;

  int get _selectedIndex => widget.selectedIndex ?? _ownIndex;

  void _select(int index) {
    final onDestinationSelected = widget.onDestinationSelected;
    if (onDestinationSelected != null) {
      onDestinationSelected(index);
      return;
    }
    setState(() => _ownIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex;
    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: widget.children),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: widget.destinations,
        onDestinationSelected: _select,
      ),
      floatingActionButton: widget.fabBuilder?.call(selectedIndex),
    );
  }
}
