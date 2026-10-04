import ExpoModulesCore
import UIKit

final class LodyNavigationHeaderView: ExpoView {
  let onAction = EventDispatcher()
  private weak var header: LodyNavigationHeader?
  private var itemsJSON = ""
  private var leftItemsJSON = ""
  private var title = ""
  private var rightItems: [UIBarButtonItem] = []
  private var leftItems: [UIBarButtonItem] = []

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    accessibilityElementsHidden = true
  }

  func setItems(_ json: String) {
    guard json != itemsJSON else { return }
    itemsJSON = json
    // UIKit lays rightBarButtonItems out right-to-left; specs read left-to-right.
    rightItems = LodyNavigationHeaderItems.decode(json) { [weak self] id in self?.onAction(["id": id]) }.reversed()
    push()
  }

  func setLeftItems(_ json: String) {
    guard json != leftItemsJSON else { return }
    leftItemsJSON = json
    leftItems = LodyNavigationHeaderItems.decode(json) { [weak self] id in self?.onAction(["id": id]) }
    push()
  }

  func setTitle(_ value: String) {
    guard value != title else { return }
    title = value
    push()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil, header == nil else { return }
    var responder = next
    while let current = responder {
      if let controller = current as? UIViewController {
        header = LodyNavigationHeader.of(controller.navigationItem)
        break
      }
      responder = current.next
    }
    push()
  }

  override func willMove(toSuperview newSuperview: UIView?) {
    if newSuperview == nil { release() }
    super.willMove(toSuperview: newSuperview)
  }

  private func push() {
    guard let header else { return }
    header.rightItems = itemsJSON.isEmpty ? nil : rightItems
    header.leftItems = leftItemsJSON.isEmpty ? nil : leftItems
    header.title = title.isEmpty ? nil : title
  }

  private func release() {
    guard let header else { return }
    if header.rightItems == rightItems { header.rightItems = nil }
    if header.leftItems == leftItems { header.leftItems = nil }
    if !title.isEmpty, header.title == title { header.title = nil }
    self.header = nil
  }
}
