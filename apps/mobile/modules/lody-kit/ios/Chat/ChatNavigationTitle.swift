import UIKit

@MainActor
enum ChatNavigationTitle {
  static func plainSubtitle(project: String, machine: String) -> String {
    [project, machine].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  static func configureButton(_ button: UIButton, title: String, subtitle: String, machine: String = "") {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    let plain = plainSubtitle(project: subtitle, machine: machine)
    configuration.subtitle = plain.isEmpty ? nil : plain
    configuration.attributedSubtitle = attributedSubtitle(project: subtitle, machine: machine)
    configuration.titleAlignment = .leading
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.subtitleLineBreakMode = .byTruncatingMiddle
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
    configuration.baseForegroundColor = .label
    configuration.titleTextAttributesTransformer = .init { attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .headline)
      return attributes
    }
    configuration.subtitleTextAttributesTransformer = .init { attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .caption1)
      attributes.foregroundColor = .secondaryLabel
      return attributes
    }
    button.configuration = configuration
    button.accessibilityLabel = [title, subtitle, machine].filter { !$0.isEmpty }.joined(separator: ", ")
    button.sizeToFit()
    button.bounds.size.height = 44
  }

  static func apply(title: String, subtitle: String, button: UIButton, to item: UINavigationItem) {
    clearNativeSubtitle(item)
    item.style = .browser
    if item.titleView !== button {
      item.titleView = button
    }
  }

  static func preserveSubtitle(_ subtitle: String, on item: UINavigationItem) {
    if #available(iOS 26.0, *) {
      item.subtitle = subtitle.isEmpty ? nil : subtitle
    }
  }

  static func clearNativeSubtitle(_ item: UINavigationItem) {
    if #available(iOS 26.0, *) {
      item.subtitle = nil
    }
  }

  static func detach(button: UIButton, from item: UINavigationItem) {
    if item.titleView === button {
      item.titleView = nil
    }
  }

  private static func attributedSubtitle(project: String, machine: String) -> AttributedString? {
    let font = UIFont.preferredFont(forTextStyle: .caption1)
    let color = UIColor.secondaryLabel
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
    ]
    let text = NSMutableAttributedString()
    func append(_ name: String, symbol: String) {
      guard !name.isEmpty else { return }
      if text.length > 0 {
        text.append(NSAttributedString(string: " · ", attributes: attributes))
      }
      if let attachment = symbolAttachment(symbol, font: font, color: color) {
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(string: " ", attributes: attributes))
      }
      text.append(NSAttributedString(string: name, attributes: attributes))
    }
    append(project, symbol: "folder")
    append(machine, symbol: "desktopcomputer")
    return text.length == 0 ? nil : AttributedString(text)
  }

  private static func symbolAttachment(_ name: String, font: UIFont, color: UIColor) -> NSTextAttachment? {
    let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(font: font.withSize(max(1, font.pointSize - 3))))?
      .withTintColor(color, renderingMode: .alwaysOriginal)
    guard let image else { return nil }
    let attachment = NSTextAttachment()
    attachment.image = image
    let offset = (font.capHeight - image.size.height) / 2
    attachment.bounds = CGRect(x: 0, y: offset, width: image.size.width, height: image.size.height)
    return attachment
  }
}
