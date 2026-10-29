import Foundation

public enum LodyStorage {
  // Unsandboxed Mac apps share ~/Library/Application Support, and the official desktop app is also named Lody.
  public static var root: URL {
    #if os(macOS)
    URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "app.innei.lody.mac")
    #else
    URL.applicationSupportDirectory
    #endif
  }
}
