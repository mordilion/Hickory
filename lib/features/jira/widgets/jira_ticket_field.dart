import 'dart:async';

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
  Timer? _debounce;
  String? _lastQuery;
  List<JiraIssueSuggestion> _suggestions = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Guards against redundant searches: RawAutocomplete's optionsBuilder can
  /// fire again with the same text (e.g. on cursor/selection-only changes,
  /// not just text edits), which would otherwise restart the debounce timer
  /// and re-query Jira for a query that hasn't actually changed.
  void _search(String query) {
    if (query == _lastQuery) return;
    _lastQuery = query;
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    try {
      final client = await ref.read(jiraClientProvider.future);
      if (client == null || !mounted) return;
      final results = await client.searchIssues(query);
      if (mounted) setState(() => _suggestions = results);
    } catch (_) {
      // Search failing (network error, provider/credentials error) must
      // never block manual entry of a ticket key.
      if (mounted) setState(() => _suggestions = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RawAutocomplete<JiraIssueSuggestion>(
      initialValue: TextEditingValue(text: widget.initialValue ?? ''),
      displayStringForOption: (option) => option.key,
      optionsBuilder: (textValue) {
        _search(textValue.text);
        return _suggestions.where(
          (s) => s.key.toLowerCase().contains(textValue.text.toLowerCase()),
        );
      },
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
