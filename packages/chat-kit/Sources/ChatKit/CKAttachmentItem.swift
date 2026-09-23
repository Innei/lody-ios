import UIKit

/// Display-only attachment. The host resolves thumbnails, localization and file access.
public struct CKAttachmentItem: Equatable {
  public let id: String
  public var name: String
  public var symbol: String
  public var thumbnail: UIImage?
  public var previewAccessibilityLabel: String
  public var removeAccessibilityLabel: String

  public init(id: String, name: String, symbol: String = "doc", thumbnail: UIImage? = nil,
              previewAccessibilityLabel: String? = nil, removeAccessibilityLabel: String? = nil) {
    self.id = id
    self.name = name
    self.symbol = symbol
    self.thumbnail = thumbnail
    self.previewAccessibilityLabel = previewAccessibilityLabel ?? "Preview \(name)"
    self.removeAccessibilityLabel = removeAccessibilityLabel ?? "Remove \(name)"
  }
}
