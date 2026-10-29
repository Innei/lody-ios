import Foundation

extension Bundle {
  // Shared sources use the shared data catalog in the app and the host bundle in extensions.
  static var lody: Bundle {
    #if SWIFT_PACKAGE
    .lodyData
    #else
    .main
    #endif
  }
}
