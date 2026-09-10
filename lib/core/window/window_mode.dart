/// Which shape the single Hickory window currently has. See
/// docs/superpowers/specs/2026-09-10-timer-pill-design.md.
enum WindowMode {
  /// The normal app window: resizable, title bar, minimum 480x960.
  full,

  /// The frameless 320x56 always-on-top timer pill.
  pill,
}
