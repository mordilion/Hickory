#include "activity_tracker_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <chrono>
#include <memory>
#include <string>

namespace activity_tracker {

namespace {

// Converts a UTF-16 Windows string to UTF-8 for the Dart side.
std::string Utf16ToUtf8(const std::wstring &utf16) {
  if (utf16.empty()) return std::string();
  int size = ::WideCharToMultiByte(CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()),
                                    nullptr, 0, nullptr, nullptr);
  std::string utf8(size, 0);
  ::WideCharToMultiByte(CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()), utf8.data(),
                        size, nullptr, nullptr);
  return utf8;
}

int64_t CurrentTimeMillisUtc() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

// The foreground window's process image base name, without the .exe
// extension, e.g. "notepad" for Notepad. Empty if it couldn't be resolved
// (e.g. a protected system process).
std::string ForegroundProcessName(HWND hwnd) {
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0) return "";

  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) return "";

  wchar_t path[MAX_PATH];
  DWORD size = MAX_PATH;
  std::string name;
  if (::QueryFullProcessImageNameW(process, 0, path, &size)) {
    std::wstring full_path(path, size);
    size_t slash = full_path.find_last_of(L"\\/");
    std::wstring file_name = slash == std::wstring::npos ? full_path : full_path.substr(slash + 1);
    size_t dot = file_name.find_last_of(L'.');
    if (dot != std::wstring::npos) file_name = file_name.substr(0, dot);
    name = Utf16ToUtf8(file_name);
  }
  ::CloseHandle(process);
  return name;
}

std::string ForegroundWindowTitle(HWND hwnd) {
  int length = ::GetWindowTextLengthW(hwnd);
  if (length <= 0) return "";
  std::wstring title(static_cast<size_t>(length) + 1, L'\0');
  int copied = ::GetWindowTextW(hwnd, title.data(), length + 1);
  title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
  return Utf16ToUtf8(title);
}

}  // namespace

// static
ActivityTrackerPlugin *ActivityTrackerPlugin::instance_ = nullptr;

// static
void ActivityTrackerPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar) {
  auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "hickory/activity_tracker",
      &flutter::StandardMethodCodec::GetInstance());
  auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "hickory/activity_tracker/events",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ActivityTrackerPlugin>();

  method_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  event_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [plugin_pointer = plugin.get()](
              const flutter::EncodableValue *arguments,
              std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events) {
            return plugin_pointer->OnListen(arguments, std::move(events));
          },
          [plugin_pointer = plugin.get()](const flutter::EncodableValue *arguments) {
            return plugin_pointer->OnCancel(arguments);
          }));

  registrar->AddPlugin(std::move(plugin));
}

ActivityTrackerPlugin::ActivityTrackerPlugin() { instance_ = this; }

ActivityTrackerPlugin::~ActivityTrackerPlugin() {
  StopWatchingForegroundWindow();
  if (instance_ == this) instance_ = nullptr;
}

void ActivityTrackerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto &method = method_call.method_name();
  if (method == "getIdleSeconds") {
    LASTINPUTINFO last_input{};
    last_input.cbSize = sizeof(LASTINPUTINFO);
    if (::GetLastInputInfo(&last_input)) {
      // dwTime is a 32-bit tick count matching GetTickCount() (not
      // GetTickCount64()); this wraps roughly every 49.7 days of uptime, an
      // accepted edge case for idle-time detection.
      DWORD idle_millis = ::GetTickCount() - last_input.dwTime;
      result->Success(flutter::EncodableValue(static_cast<int>(idle_millis / 1000)));
    } else {
      result->Success(flutter::EncodableValue(0));
    }
  } else if (method == "hasPermissions" || method == "requestPermissions") {
    // Windows needs no special permission for foreground-window/idle
    // tracking.
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> ActivityTrackerPlugin::OnListen(
    const flutter::EncodableValue *arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events) {
  event_sink_ = std::move(events);
  StartWatchingForegroundWindow();
  EmitCurrentForegroundWindow();
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> ActivityTrackerPlugin::OnCancel(
    const flutter::EncodableValue *arguments) {
  StopWatchingForegroundWindow();
  event_sink_ = nullptr;
  return nullptr;
}

void ActivityTrackerPlugin::StartWatchingForegroundWindow() {
  if (event_hook_) return;
  event_hook_ = ::SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr,
                                   &ActivityTrackerPlugin::WinEventProc, 0, 0,
                                   WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
}

void ActivityTrackerPlugin::StopWatchingForegroundWindow() {
  if (!event_hook_) return;
  ::UnhookWinEvent(event_hook_);
  event_hook_ = nullptr;
}

void ActivityTrackerPlugin::EmitCurrentForegroundWindow() {
  HWND hwnd = ::GetForegroundWindow();
  if (!hwnd || !event_sink_) return;

  std::string app_name = ForegroundProcessName(hwnd);
  if (app_name.empty()) return;
  std::string window_title = ForegroundWindowTitle(hwnd);

  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("appName")] = flutter::EncodableValue(app_name);
  payload[flutter::EncodableValue("windowTitle")] =
      window_title.empty() ? flutter::EncodableValue() : flutter::EncodableValue(window_title);
  payload[flutter::EncodableValue("observedAtMillis")] =
      flutter::EncodableValue(CurrentTimeMillisUtc());

  event_sink_->Success(flutter::EncodableValue(payload));
}

// static
void CALLBACK ActivityTrackerPlugin::WinEventProc(HWINEVENTHOOK hook, DWORD event, HWND hwnd,
                                                    LONG id_object, LONG id_child,
                                                    DWORD event_thread, DWORD event_time) {
  if (event != EVENT_SYSTEM_FOREGROUND || !instance_) return;
  // Only whole-window foreground changes matter, not clicks on child
  // controls within the same window.
  if (id_object != OBJID_WINDOW) return;
  instance_->EmitCurrentForegroundWindow();
}

}  // namespace activity_tracker
