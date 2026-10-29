import Foundation

extension Bundle {
  // Shared sources use the package bundle in apps and the host bundle in extensions.
  public static var lodyData: Bundle {
    #if SWIFT_PACKAGE
    .module
    #else
    .main
    #endif
  }
}
