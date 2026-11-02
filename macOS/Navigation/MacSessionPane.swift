import AppKit
import LodyData

@MainActor
protocol MacSessionPane: NSViewController {
  func setStreaming(_ on: Bool)
  var inspectionModel: MacInspectionModel? { get }
  var onInspect: (() -> Void)? { get set }
}

extension MacSessionPane {
  var inspectionModel: MacInspectionModel? { nil }
  var onInspect: (() -> Void)? { get { nil } set {} }
}
