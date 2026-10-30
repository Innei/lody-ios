import AppKit

@main
@MainActor
enum LodyMacMain {
  static func main() {
    let application = NSApplication.shared
    let delegate = LodyMacAppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
  }
}
