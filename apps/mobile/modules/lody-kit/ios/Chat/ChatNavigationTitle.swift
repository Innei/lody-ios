import UIKit

enum ChatNavigationTitle {
  static func configureButton(_ button: UIButton, title: String, subtitle: String) {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.subtitle = subtitle.isEmpty ? nil : subtitle
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
    button.accessibilityLabel = [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    button.sizeToFit()
    button.bounds.size.height = 44
  }

  static func apply(title: String, subtitle: String, button: UIButton, to item: UINavigationItem) {
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
}
