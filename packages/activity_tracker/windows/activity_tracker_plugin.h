#ifndef FLUTTER_PLUGIN_ACTIVITY_TRACKER_PLUGIN_H_
#define FLUTTER_PLUGIN_ACTIVITY_TRACKER_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

// windows.h must come after the flutter headers above.
#include <windows.h>

#include <memory>

namespace activity_tracker {

class ActivityTrackerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ActivityTrackerPlugin();
  virtual ~ActivityTrackerPlugin();

  // Disallow copy and assign.
  ActivityTrackerPlugin(const ActivityTrackerPlugin &) = delete;
  ActivityTrackerPlugin &operator=(const ActivityTrackerPlugin &) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListen(
      const flutter::EncodableValue *arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events);

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancel(
      const flutter::EncodableValue *arguments);

  void StartWatchingForegroundWindow();
  void StopWatchingForegroundWindow();
  void EmitCurrentForegroundWindow();

  HWINEVENTHOOK event_hook_ = nullptr;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  static void CALLBACK WinEventProc(HWINEVENTHOOK hook, DWORD event, HWND hwnd,
                                     LONG id_object, LONG id_child,
                                     DWORD event_thread, DWORD event_time);

  // SetWinEventHook only accepts a free function, so the callback reaches
  // back into the one live plugin instance through this pointer. Safe
  // because exactly one ActivityTrackerPlugin is ever registered.
  static ActivityTrackerPlugin *instance_;
};

}  // namespace activity_tracker

#endif  // FLUTTER_PLUGIN_ACTIVITY_TRACKER_PLUGIN_H_
