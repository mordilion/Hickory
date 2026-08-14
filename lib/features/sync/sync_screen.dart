// lib/features/sync/sync_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/jira_providers.dart';
import '../../core/di/personio_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../jira/jira_credentials_store.dart';
import '../personio/personio_credentials_store.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;
  String? _statusMessage;
  final _jiraBaseUrlController = TextEditingController();
  final _jiraEmailController = TextEditingController();
  final _jiraApiTokenController = TextEditingController();
  bool _jiraBusy = false;
  String? _jiraStatusMessage;

  final _personioClientIdController = TextEditingController();
  final _personioClientSecretController = TextEditingController();
  final _personioEmployeeIdController = TextEditingController();
  bool _personioBusy = false;
  String? _personioStatusMessage;
  DateTime _personioFrom = DateTime.now();
  DateTime _personioTo = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadJiraCredentials();
    _loadPersonioCredentials();
    _initPersonioRange();
  }

  Future<void> _loadJiraCredentials() async {
    final credentials = await ref.read(jiraCredentialsProvider.future);
    if (!mounted || credentials == null) return;
    _jiraBaseUrlController.text = credentials.baseUrl;
    _jiraEmailController.text = credentials.email;
    _jiraApiTokenController.text = credentials.apiToken;
  }

  Future<void> _loadPersonioCredentials() async {
    final credentials = await ref.read(personioCredentialsProvider.future);
    if (!mounted || credentials == null) return;
    _personioClientIdController.text = credentials.clientId;
    _personioClientSecretController.text = credentials.clientSecret;
    _personioEmployeeIdController.text = credentials.employeeId;
  }

  /// Defaults the push range to "the day after the last successful push"
  /// through today, per the design's push-range default.
  Future<void> _initPersonioRange() async {
    final latest = await ref.read(personioLatestSyncedAtProvider.future);
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _personioFrom = latest == null
          ? DateTime(now.year, now.month, now.day)
          : DateTime(
              latest.year,
              latest.month,
              latest.day,
            ).add(const Duration(days: 1));
      _personioTo = DateTime(now.year, now.month, now.day);
    });
  }

  @override
  void dispose() {
    _jiraBaseUrlController.dispose();
    _jiraEmailController.dispose();
    _jiraApiTokenController.dispose();
    _personioClientIdController.dispose();
    _personioClientSecretController.dispose();
    _personioEmployeeIdController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final picked = await pickAndApplySyncFolder(ref);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _statusMessage = picked == null ? null : l10n.syncFolderChosen(picked);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final ingestor = await ref.read(syncIngestorProvider.future);
      await ingestor.syncNow();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _statusMessage = l10n.syncCompleted);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Light client-side validation before writing credentials: catches empty
  /// fields and an obviously-malformed base URL early, so the far more
  /// common failure mode (a typo right after first setup) surfaces as an
  /// immediate, specific message instead of a confusing "not configured" or
  /// unhandled error the first time the URL is actually used.
  bool _hasValidJiraCredentialsInput() {
    final email = _jiraEmailController.text.trim();
    final apiToken = _jiraApiTokenController.text.trim();
    if (email.isEmpty || apiToken.isEmpty) return false;
    final uri = Uri.tryParse(_jiraBaseUrlController.text.trim());
    return uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _saveJiraCredentials() async {
    final l10n = AppLocalizations.of(context);
    if (!_hasValidJiraCredentialsInput()) {
      setState(() => _jiraStatusMessage = l10n.syncJiraInvalidCredentials);
      return;
    }
    setState(() {
      _jiraBusy = true;
      _jiraStatusMessage = null;
    });
    try {
      final store = ref.read(jiraCredentialsStoreProvider);
      await store.write(
        JiraCredentials(
          baseUrl: _jiraBaseUrlController.text.trim(),
          email: _jiraEmailController.text.trim(),
          apiToken: _jiraApiTokenController.text.trim(),
        ),
      );
      ref.invalidate(jiraCredentialsProvider);
      if (mounted) {
        setState(() => _jiraStatusMessage = l10n.syncJiraCredentialsSaved);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _jiraStatusMessage = l10n.syncJiraUnexpectedError);
      }
    } finally {
      if (mounted) setState(() => _jiraBusy = false);
    }
  }

  Future<void> _testJiraConnection() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _jiraBusy = true;
      _jiraStatusMessage = null;
    });
    try {
      final client = await ref.read(jiraClientProvider.future);
      if (client == null) {
        if (mounted) {
          setState(() => _jiraStatusMessage = l10n.syncJiraNotConfigured);
        }
        return;
      }
      final ok = await client.testConnection();
      if (!mounted) return;
      setState(
        () => _jiraStatusMessage = ok
            ? l10n.syncJiraTestConnectionSuccess
            : l10n.syncJiraTestConnectionFailure,
      );
    } catch (_) {
      // testConnection() throws for transport-level errors (e.g. a
      // malformed URL, DNS failure) — the single most likely error right
      // after first configuring credentials, so this must not be left to
      // propagate unhandled.
      if (mounted) {
        setState(() => _jiraStatusMessage = l10n.syncJiraTestConnectionFailure);
      }
    } finally {
      if (mounted) setState(() => _jiraBusy = false);
    }
  }

  Future<void> _syncJiraNow() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _jiraBusy = true;
      _jiraStatusMessage = null;
    });
    try {
      final service = await ref.read(jiraSyncServiceProvider.future);
      if (service == null) {
        if (mounted) {
          setState(() => _jiraStatusMessage = l10n.syncJiraNotConfigured);
        }
        return;
      }
      final result = await service.syncNow();
      if (!mounted) return;
      setState(
        () => _jiraStatusMessage = l10n.syncJiraSyncResult(
          result.created,
          result.updated,
          result.deleted,
          result.failed,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _jiraStatusMessage = l10n.syncJiraUnexpectedError);
      }
    } finally {
      if (mounted) setState(() => _jiraBusy = false);
    }
  }

  bool _hasValidPersonioCredentialsInput() {
    return _personioClientIdController.text.trim().isNotEmpty &&
        _personioClientSecretController.text.trim().isNotEmpty &&
        _personioEmployeeIdController.text.trim().isNotEmpty;
  }

  Future<void> _savePersonioCredentials() async {
    final l10n = AppLocalizations.of(context);
    if (!_hasValidPersonioCredentialsInput()) {
      setState(
        () => _personioStatusMessage = l10n.syncPersonioInvalidCredentials,
      );
      return;
    }
    setState(() {
      _personioBusy = true;
      _personioStatusMessage = null;
    });
    try {
      final store = ref.read(personioCredentialsStoreProvider);
      await store.write(
        PersonioCredentials(
          clientId: _personioClientIdController.text.trim(),
          clientSecret: _personioClientSecretController.text.trim(),
          employeeId: _personioEmployeeIdController.text.trim(),
        ),
      );
      ref.invalidate(personioCredentialsProvider);
      if (mounted) {
        setState(
          () => _personioStatusMessage = l10n.syncPersonioCredentialsSaved,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _personioStatusMessage = l10n.syncPersonioUnexpectedError,
        );
      }
    } finally {
      if (mounted) setState(() => _personioBusy = false);
    }
  }

  Future<void> _testPersonioConnection() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _personioBusy = true;
      _personioStatusMessage = null;
    });
    try {
      final client = await ref.read(personioClientProvider.future);
      if (client == null) {
        if (mounted) {
          setState(
            () => _personioStatusMessage = l10n.syncPersonioNotConfigured,
          );
        }
        return;
      }
      final ok = await client.testConnection();
      if (!mounted) return;
      setState(
        () => _personioStatusMessage = ok
            ? l10n.syncPersonioTestConnectionSuccess
            : l10n.syncPersonioTestConnectionFailure,
      );
    } catch (_) {
      // testConnection() throws for transport-level errors (e.g. a
      // malformed URL, DNS failure) -- the single most likely error right
      // after first configuring credentials, so this must not be left to
      // propagate unhandled.
      if (mounted) {
        setState(
          () => _personioStatusMessage = l10n.syncPersonioTestConnectionFailure,
        );
      }
    } finally {
      if (mounted) setState(() => _personioBusy = false);
    }
  }

  Future<void> _pushPersonio() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _personioBusy = true;
      _personioStatusMessage = null;
    });
    try {
      final service = await ref.read(personioSyncServiceProvider.future);
      if (service == null) {
        if (mounted) {
          setState(
            () => _personioStatusMessage = l10n.syncPersonioNotConfigured,
          );
        }
        return;
      }
      final result = await service.pushRange(
        from: _personioFrom,
        to: _personioTo,
      );
      ref.invalidate(personioLatestSyncedAtProvider);
      if (!mounted) return;
      setState(
        () => _personioStatusMessage = l10n.syncPersonioPushResult(
          result.created,
          result.updated,
          result.deleted,
          result.failed,
        ),
      );
      // Advance the visible range immediately (not just the invalidated
      // provider, which nothing rebuilds against) -- the range must keep
      // moving forward after a push without requiring the user to leave
      // and reopen this screen.
      await _initPersonioRange();
    } catch (_) {
      if (mounted) {
        setState(
          () => _personioStatusMessage = l10n.syncPersonioUnexpectedError,
        );
      }
    } finally {
      if (mounted) setState(() => _personioBusy = false);
    }
  }

  Future<void> _pickPersonioFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _personioFrom,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _personioFrom = picked);
  }

  Future<void> _pickPersonioTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _personioTo,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _personioTo = picked);
  }

  /// Plain `YYYY-MM-DD`, deliberately not the app's locale-aware date
  /// format (`core/format/date_format.dart`) -- this label is a compact
  /// picker-button caption, not user-facing report content, so pulling in
  /// the full date-format settings dependency here isn't worth it.
  String _formatPersonioDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final folderAsync = ref.watch(configuredSyncFolderPathProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.syncTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    folderAsync.when(
                      data: (path) => Text(
                        path == null
                            ? l10n.syncNoFolderSelected
                            : l10n.syncFolderPath(path),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text(l10n.syncError('$e')),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.syncFolderDescription,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _statusMessage!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: _busy ? null : _syncNow,
                          child: Text(l10n.syncNowButton),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _pickFolder,
                          child: Text(l10n.syncChooseFolderButton),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Card(
              child: ExpansionTile(
                title: Text(
                  l10n.syncJiraSectionTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                initiallyExpanded: false,
                // ExpansionTile draws a top/bottom divider line in the theme's
                // divider color while expanded by default (see shape/
                // collapsedShape in Flutter's expansion_tile.dart) -- inside a
                // Card, that clashes with the Card's own border, so both are
                // disabled here.
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _jiraBaseUrlController,
                          decoration: InputDecoration(
                            labelText: l10n.syncJiraBaseUrlLabel,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _jiraEmailController,
                          decoration: InputDecoration(
                            labelText: l10n.syncJiraEmailLabel,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _jiraApiTokenController,
                          decoration: InputDecoration(
                            labelText: l10n.syncJiraApiTokenLabel,
                          ),
                          obscureText: true,
                        ),
                        if (_jiraStatusMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _jiraStatusMessage!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: _jiraBusy
                                  ? null
                                  : _saveJiraCredentials,
                              child: Text(l10n.syncJiraSaveCredentialsButton),
                            ),
                            OutlinedButton(
                              onPressed: _jiraBusy ? null : _testJiraConnection,
                              child: Text(l10n.syncJiraTestConnectionButton),
                            ),
                            OutlinedButton(
                              onPressed: _jiraBusy ? null : _syncJiraNow,
                              child: Text(l10n.syncJiraSyncButton),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Card(
              child: ExpansionTile(
                title: Text(
                  l10n.syncPersonioSectionTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                initiallyExpanded: false,
                // ExpansionTile draws a top/bottom divider line in the theme's
                // divider color while expanded by default (see shape/
                // collapsedShape in Flutter's expansion_tile.dart) -- inside a
                // Card, that clashes with the Card's own border, so both are
                // disabled here.
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _personioClientIdController,
                          decoration: InputDecoration(
                            labelText: l10n.syncPersonioClientIdLabel,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _personioClientSecretController,
                          decoration: InputDecoration(
                            labelText: l10n.syncPersonioClientSecretLabel,
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _personioEmployeeIdController,
                          decoration: InputDecoration(
                            labelText: l10n.syncPersonioEmployeeIdLabel,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: _personioBusy
                                  ? null
                                  : _savePersonioCredentials,
                              child: Text(
                                l10n.syncPersonioSaveCredentialsButton,
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _personioBusy
                                  ? null
                                  : _testPersonioConnection,
                              child: Text(
                                l10n.syncPersonioTestConnectionButton,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _personioBusy
                                    ? null
                                    : _pickPersonioFrom,
                                child: Text(
                                  '${l10n.syncPersonioFromLabel}: '
                                  '${_formatPersonioDate(_personioFrom)}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _personioBusy
                                    ? null
                                    : _pickPersonioTo,
                                child: Text(
                                  '${l10n.syncPersonioToLabel}: '
                                  '${_formatPersonioDate(_personioTo)}',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_personioStatusMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _personioStatusMessage!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _personioBusy ? null : _pushPersonio,
                          child: Text(l10n.syncPersonioPushButton),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
