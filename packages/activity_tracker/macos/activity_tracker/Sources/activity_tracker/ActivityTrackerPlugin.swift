import ApplicationServices
import Cocoa
import FlutterMacOS

// NOTE: Written against documented Apple APIs (NSWorkspace, Accessibility,
// CGEventSource) but could not be built or run on this development machine
// (no macOS available) — treat as unverified until it's actually built and
// exercised on a Mac.
public class ActivityTrackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var activationObserver: NSObjectProtocol?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ActivityTrackerPlugin()

    let methodChannel = FlutterMethodChannel(
      name: "hickory/activity_tracker",
      binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: "hickory/activity_tracker/events",
      binaryMessenger: registrar.messenger)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getIdleSeconds":
      // rawValue ~0 is the documented sentinel for "time since the last
      // event of any type", as opposed to a specific CGEventType.
      let idle = CGEventSource.secondsSinceLastEventType(
        .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
      result(Int(idle))
    case "hasPermissions":
      result(AXIsProcessTrusted())
    case "requestPermissions":
      let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
      let granted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
      result(granted)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    // No special permission is needed just to observe *which app* is
    // frontmost — only reading its window *title* needs Accessibility (see
    // windowTitle(forPid:) below), so this works even before that's granted.
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.emitCurrentApplication(from: notification)
    }
    emitCurrentApplication(from: nil)
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let activationObserver = activationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
    }
    activationObserver = nil
    eventSink = nil
    return nil
  }

  private func emitCurrentApplication(from notification: Notification?) {
    guard let eventSink = eventSink else { return }

    let app: NSRunningApplication?
    if let activatedApp = notification?.userInfo?[NSWorkspace.applicationUserInfoKey]
      as? NSRunningApplication
    {
      app = activatedApp
    } else {
      app = NSWorkspace.shared.frontmostApplication
    }

    guard let app = app, let appName = app.localizedName else { return }

    var payload: [String: Any] = [
      "appName": appName,
      "observedAtMillis": Int64(Date().timeIntervalSince1970 * 1000),
    ]
    payload["windowTitle"] = windowTitle(forPid: app.processIdentifier) ?? NSNull()

    eventSink(payload)
  }

  /// Requires the Accessibility permission; returns nil (graceful
  /// degradation to an app-name-only sample) if it hasn't been granted.
  private func windowTitle(forPid pid: pid_t) -> String? {
    guard AXIsProcessTrusted() else { return nil }

    let appRef = AXUIElementCreateApplication(pid)
    var focusedWindow: AnyObject?
    let windowResult = AXUIElementCopyAttributeValue(
      appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow)
    guard windowResult == .success, let window = focusedWindow else { return nil }

    var titleValue: AnyObject?
    let titleResult = AXUIElementCopyAttributeValue(
      window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
    guard titleResult == .success else { return nil }
    return titleValue as? String
  }
}
