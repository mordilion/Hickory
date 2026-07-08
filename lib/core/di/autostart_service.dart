import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Thin wrapper around launch_at_startup so the rest of the app depends on
/// a small local interface instead of the package directly.
class AutostartService {
  Future<void> setup() async {
    final packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      packageName: 'com.hickory.hickory',
    );
  }

  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  Future<void> setEnabled(bool value) {
    return value ? launchAtStartup.enable() : launchAtStartup.disable();
  }
}

final autostartServiceProvider = Provider<AutostartService>((ref) => AutostartService());
