import UIKit

/// Per-instance semantic colors. Dynamic UIColors remain unresolved until UIKit draws them.
@MainActor
public struct CKTheme {
  public var tintColor: UIColor = .systemBlue
  public var textColor: UIColor = .label
  public var secondaryTextColor: UIColor = .secondaryLabel
  public var mutedTextColor: UIColor = .tertiaryLabel
  public init() {}
  public static var system: CKTheme { CKTheme() }
}

/// Attachment geometry and typography, independent of upload or file storage.
@MainActor
public struct CKAttachmentStyle {
  public var theme: CKTheme
  public var font: UIFont = .systemFont(ofSize: 13)
  public var spacing: CGFloat = 8
  public var maximumWidth: CGFloat = 200
  public var height: CGFloat = 34
  public var cornerRadius: CGFloat? = nil
  public var removeSymbol: String = "xmark.circle.fill"
  public init(theme: CKTheme = .system) { self.theme = theme }
}
