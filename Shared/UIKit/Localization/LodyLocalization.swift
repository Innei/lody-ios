import Foundation

extension Bundle {
  // LodyData owns the catalog in the app; extensions compile its bundle accessor locally.
  static var lody: Bundle { .lodyData }
}
