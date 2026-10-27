// StateProvider moved to this entry point in Riverpod 3.x; still the right
// tool for a single directly-settable flag -- same reasoning as the
// providers in core/di/update_providers.dart.
import 'package:flutter_riverpod/legacy.dart';

/// Asks the Settings tab to push its update page; the tab clears the flag
/// once it has pushed.
///
/// Exists because that tab owns a private Navigator (see
/// settings_screen.dart), so a caller outside it -- the startup update
/// prompt in AppShell -- has no way to push onto that stack directly.
final openUpdatePageRequestedProvider = StateProvider<bool>((ref) => false);
