import '../../data/drift/database.dart' show AppSettingsRow;

/// Default presets shown as quick-add duration chips before the user
/// customizes them in Settings, and the fallback used whenever the stored
/// value is missing or unparseable.
const defaultQuickAddDurationsMinutes = [15, 30, 45, 60];

/// Parses the comma-separated minutes list stored in
/// `AppSettings.quickAddDurationsMinutes`. Invalid, non-positive, and
/// duplicate entries are dropped; falls back to
/// [defaultQuickAddDurationsMinutes] if nothing valid remains (including a
/// null/empty [raw]) so a corrupted value never breaks the quick-add bar.
List<int> parseQuickAddDurations(String? raw) {
  if (raw == null || raw.trim().isEmpty) return defaultQuickAddDurationsMinutes;
  final values = raw
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .where((v) => v != null && v > 0)
      .map((v) => v!)
      .toSet()
      .toList()
    ..sort();
  return values.isEmpty ? defaultQuickAddDurationsMinutes : values;
}

/// Inverse of [parseQuickAddDurations], for writing the setting back.
String formatQuickAddDurations(List<int> minutes) => minutes.join(',');

extension AppSettingsQuickAddDurations on AppSettingsRow? {
  List<int> get quickAddDurations => parseQuickAddDurations(this?.quickAddDurationsMinutes);
}
