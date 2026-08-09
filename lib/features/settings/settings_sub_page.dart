import 'package:flutter/material.dart';

/// Shared chrome for a Settings sub-page: a back button (optionally next to
/// a page title) above scrollable [child] content. [title] is omitted when
/// [child]'s own first widget already renders an equivalent heading -- see
/// docs/superpowers/specs/2026-08-08-settings-reorganization-design.md
/// section 2 for which categories that applies to (passing both would show
/// the same text twice).
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BackButton(),
                if (title != null) ...[
                  const SizedBox(width: 8),
                  Text(title!, style: Theme.of(context).textTheme.headlineSmall),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}
