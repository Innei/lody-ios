import UIKit

@MainActor
final class AppIconController: UIViewController {
  private let grid = LodyAppIconGrid(appContext: nil)
  private var observer: NSObjectProtocol?
  private var pending = ""

  init() {
    super.init(nibName: nil, bundle: nil)
    title = LodyStrings.text("settings.appearance.appIcon")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit { observer.map(NotificationCenter.default.removeObserver) }

  override func viewDidLoad() {
    super.viewDidLoad()
    grid.frame = view.bounds
    grid.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    grid.setItems([
      LodyAppIconItem(id: "default", title: LodyStrings.text("settings.appearance.defaultIcon")),
      LodyAppIconItem(id: "Aqua", title: "Aqua"),
    ])
    grid.selectHandler = { [weak self] id in self?.select(id) }
    view.addSubview(grid)
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.render() }
    }
    render()
  }

  private func render() {
    grid.setSelected(LodyAppIcon.current)
    grid.setPending(pending)
    grid.setEnabled(pending.isEmpty)
  }

  private func select(_ id: String) {
    guard pending.isEmpty, id != LodyAppIcon.current else { return }
    pending = id
    render()
    LodyAppIcon.set(id) { [weak self] result in
      guard let self else { return }
      pending = ""
      render()
      if case .failure = result { showFailure() }
    }
  }

  private func showFailure() {
    let alert = UIAlertController(
      title: LodyStrings.text("settings.appearance.appIcon"),
      message: LodyStrings.text("settings.appearance.iconFailed"),
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.ok"), style: .default))
    present(alert, animated: true)
  }
}
