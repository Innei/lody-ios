import LodyCore
import Foundation

/// Launch-argument fixtures. Available in Debug and Release; only `--ui-verify`
/// (or `--lody-offline`) turns them on. TestFlight never passes those arguments.
public enum LodyUIVerify {
  public static var enabled: Bool { has("--ui-verify") }
  public static var offline: Bool { enabled || has("--lody-offline") }
  public static var home: Bool { enabled && has("--ui-verify-home") }
  public static var mentions: Bool { enabled && has("--ui-verify-mentions") }
  public static var throwProbe: Bool { enabled && has("--ui-verify-throw") }
  public static var scroll: Bool {
    enabled && (has("--ui-verify-scroll") || has("--ui-verify-opening"))
  }

  public static func has(_ flag: String) -> Bool {
    ProcessInfo.processInfo.arguments.contains(flag)
  }
}
