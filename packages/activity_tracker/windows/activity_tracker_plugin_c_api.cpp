#include "include/activity_tracker/activity_tracker_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "activity_tracker_plugin.h"

void ActivityTrackerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  activity_tracker::ActivityTrackerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
