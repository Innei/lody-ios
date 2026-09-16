import Foundation

/// Launch-argument fixtures. Available in Debug and Release; only `--ui-verify`
/// (or `--lody-offline`) turns them on. TestFlight never passes those arguments.
enum LodyUIVerify {
  static var enabled: Bool { has("--ui-verify") }
  static var offline: Bool { has("--lody-offline") }
  static var home: Bool { enabled && has("--ui-verify-home") }
  static var mentions: Bool { enabled && has("--ui-verify-mentions") }
  static var throwProbe: Bool { enabled && has("--ui-verify-throw") }
  static var scroll: Bool {
    enabled && (has("--ui-verify-scroll") || has("--ui-verify-opening"))
  }

  static func has(_ flag: String) -> Bool {
    ProcessInfo.processInfo.arguments.contains(flag)
  }
}
