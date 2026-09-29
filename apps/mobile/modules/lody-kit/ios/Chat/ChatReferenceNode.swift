import Lexical
import UIKit

extension NodeType {
  static let lodyReference = NodeType(rawValue: "lody-reference")
}

// A token-mode text node, as in Lexical's own mention node: its text is the exact reference the agent receives.
final class ChatReferenceNode: TextNode {
  required init(text: String, key: NodeKey?) {
    super.init(text: text, key: key)
    mode = .token
  }

  required init(from decoder: Decoder) throws {
    try super.init(from: decoder)
  }

  override class func getType() -> NodeType { .lodyReference }

  override func clone() -> Self {
    Self(text: getText_dangerousPropertyAccess(), key: key)
  }

  override func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any] {
    var attributes = super.getAttributedStringAttributes(theme: theme)
    attributes[.foregroundColor] = UIColor.lodyAccent
    return attributes
  }
}
