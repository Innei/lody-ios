import AppKit
import LodyData

@MainActor
protocol MacSessionPane: NSViewController {
  func setStreaming(_ on: Bool)
}
