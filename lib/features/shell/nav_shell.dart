import 'package:flutter/material.dart';

/// A generic bottom-navigation container: index state, an IndexedStack of
/// [children], a NavigationBar built from [destinations], and an optional
/// per-tab floating action button via [fabBuilder]. Has no Riverpod (or any
/// other app-specific) dependency on purpose — see AppShell for the real
/// wiring, and Task 10 in the implementation plan for why that split
/// exists (keeps this widget cheaply testable with dummy children).
class NavShell extends StatefulWidget {
  const NavShell({
    super.key,
    required this.children,
    required this.destinations,
    this.initialIndex = 0,
    this.fabBuilder,
  }) : assert(children.length == destinations.length);

  final List<Widget> children;
  final List<NavigationDestination> destinations;
  final int initialIndex;
  final Widget? Function(int selectedIndex)? fabBuilder;

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  late int _selectedIndex = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: widget.children),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: widget.destinations,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      ),
      floatingActionButton: widget.fabBuilder?.call(_selectedIndex),
    );
  }
}
