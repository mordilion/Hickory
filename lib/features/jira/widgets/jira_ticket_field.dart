import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/jira_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../jira_client.dart';

/// A Jira ticket-key input: does a debounced Jira issue search as the user
/// types when Jira is configured, and always still accepts a manually
/// typed key — search failing, or Jira not being configured yet, must
/// never block entering or editing a time entry.
class JiraTicketField extends ConsumerStatefulWidget {
  const JiraTicketField({super.key, required this.initialValue, required this.onChanged});

  final String? initialValue;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<JiraTicketField> createState() => _JiraTicketFieldState();
}

class _JiraTicketFieldState extends ConsumerState<JiraTicketField> {
  /// RawAutocomplete's `optionsBuilder` is typed `FutureOr<Iterable<T>>`
  /// specifically so an async options source is supported natively:
  /// RawAutocomplete tracks the in-flight call itself and discards a result
  /// that resolves after a newer call has already started, so returning a
  /// Future here — rather than kicking off a search as a side effect and
  /// pushing results back in via a separate `setState`, which does NOT
  /// cause RawAutocomplete to re-run `optionsBuilder` or redraw the options
  /// list — is what actually gets fetched results displayed. The debounce
  /// is a plain delay at the start of the call; a query that goes stale
  /// during the delay is simply superseded by RawAutocomplete's own
  /// tracking once the newer call resolves, without extra bookkeeping here.
  Future<Iterable<JiraIssueSuggestion>> _search(TextEditingValue textValue) async {
    final query = textValue.text;
    if (query.trim().isEmpty) return const [];
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      final client = await ref.read(jiraClientProvider.future);
      if (client == null) return const [];
      return await client.searchIssues(query);
    } catch (_) {
      // Search failing (network error, provider/credentials error) must
      // never block manual entry of a ticket key.
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RawAutocomplete<JiraIssueSuggestion>(
      initialValue: TextEditingValue(text: widget.initialValue ?? ''),
      displayStringForOption: (option) => option.key,
      optionsBuilder: _search,
      onSelected: (option) => widget.onChanged(option.key),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: l10n.jiraTicketFieldLabel),
          onChanged: (value) => widget.onChanged(value.trim().isEmpty ? null : value.trim()),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        if (list.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final option = list[index];
                  return ListTile(
                    title: Text(option.key),
                    subtitle: Text(option.summary),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
