import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/locale_provider.dart';
import '../../core/locale/locale_resolution.dart';
import '../../l10n/app_localizations.dart';

/// Sentinel dropdown value for "follow the system locale" (the stored
/// preference is absent in that case, so there is no language code to use).
const _systemValue = 'system';

class LanguageDropdown extends ConsumerWidget {
  const LanguageDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final explicit = ref.watch(localeControllerProvider).value;
    final systemResolved =
        resolveLocale(WidgetsBinding.instance.platformDispatcher.locale);
    final systemName = languageDisplayNames[systemResolved.languageCode]!;

    return DropdownButtonFormField<String>(
      initialValue: explicit?.languageCode ?? _systemValue,
      decoration: InputDecoration(labelText: l10n.settingsLanguage),
      items: [
        DropdownMenuItem(
          value: _systemValue,
          child: Text(l10n.settingsLanguageSystem(systemName)),
        ),
        for (final locale in supportedLocales)
          DropdownMenuItem(
            value: locale.languageCode,
            child: Text(languageDisplayNames[locale.languageCode]!),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        ref
            .read(localeControllerProvider.notifier)
            .setLocale(value == _systemValue ? null : Locale(value));
      },
    );
  }
}
