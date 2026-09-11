import ExpoModulesCore
import UIKit

/// Full-height picker hosted by the shared present/page contract.
final class LodyMentionPickerView: ExpoView, UICollectionViewDataSource, UICollectionViewDelegate {
  let onPick = EventDispatcher()
  let onQueryReset = EventDispatcher()
  let onRetry = EventDispatcher()
  private let notice = UIButton(type: .system)
  private var noticeHeight: NSLayoutConstraint!
  private var query = ""
  private let location = UIButton(type: .system)
  private let useDirectory = UIButton(type: .system)
  private let empty = UILabel()
  private let list: UICollectionView
  private var items: [ChatMentionItem] = []
  private var rows: [ChatMentionItem] = []
  private var category = "file"
  private var path = ""
  private var breadcrumbHeight: NSLayoutConstraint!
  private weak var scrollOwner: UIViewController?

  required init(appContext: AppContext? = nil) {
    var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
    config.backgroundColor = .systemGroupedBackground
    list = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
    super.init(appContext: appContext)
    backgroundColor = .systemGroupedBackground
    location.contentHorizontalAlignment = .leading
    location.titleLabel?.font = .dynamic(of: 13, weight: .medium)
    location.tintColor = .secondaryLabel
    location.accessibilityIdentifier = "mention-picker-back"
    location.addTarget(self, action: #selector(back), for: .touchUpInside)
    useDirectory.titleLabel?.font = .dynamic(of: 14, weight: .medium)
    useDirectory.accessibilityIdentifier = "mention-picker-use-directory"
    useDirectory.addTarget(self, action: #selector(pickDirectory), for: .touchUpInside)
    list.dataSource = self
    list.delegate = self
    list.keyboardDismissMode = .onDrag
    list.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "item")
    if #available(iOS 26.0, *) {
      list.topEdgeEffect.style = .soft
      list.bottomEdgeEffect.style = .soft
    }
    empty.text = LodyStrings.text("native.chat.mention.empty")
    empty.textColor = .secondaryLabel
    empty.font = .dynamic(of: 15)
    empty.textAlignment = .center
    empty.accessibilityIdentifier = "mention-picker-empty"
    notice.titleLabel?.font = .dynamic(of: 13)
    notice.titleLabel?.numberOfLines = 2
    notice.addTarget(self, action: #selector(retry), for: .touchUpInside)
    notice.accessibilityIdentifier = "mention-picker-notice"
    for view in [list, location, useDirectory, empty, notice] {
      addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    breadcrumbHeight = location.heightAnchor.constraint(equalToConstant: 0)
    noticeHeight = notice.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      notice.topAnchor.constraint(equalTo: location.bottomAnchor),
      notice.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      notice.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), noticeHeight,
      location.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      location.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      breadcrumbHeight,
      useDirectory.centerYAnchor.constraint(equalTo: location.centerYAnchor),
      useDirectory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      useDirectory.leadingAnchor.constraint(greaterThanOrEqualTo: location.trailingAnchor, constant: 12),
      useDirectory.heightAnchor.constraint(equalToConstant: 44),
      list.topAnchor.constraint(equalTo: topAnchor),
      list.leadingAnchor.constraint(equalTo: leadingAnchor), list.trailingAnchor.constraint(equalTo: trailingAnchor),
      list.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
      empty.centerXAnchor.constraint(equalTo: list.centerXAnchor), empty.centerYAnchor.constraint(equalTo: list.centerYAnchor),
    ])
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      scrollOwner?.setContentScrollView(nil, for: .top)
      scrollOwner?.setContentScrollView(nil, for: .bottom)
      scrollOwner = nil
      return
    }
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController {
        controller.setContentScrollView(list, for: .top)
        controller.setContentScrollView(list, for: .bottom)
        scrollOwner = controller
        controller.definesPresentationContext = true
        break
      }
      responder = current.next
    }
  }

  func configure(_ json: String) {
    struct Configuration: Decodable { let category: String; let items: [ChatMentionItem]; var query: String?; var notice: String? }
    guard let data = json.data(using: .utf8), let value = try? JSONDecoder().decode(Configuration.self, from: data) else { return }
    category = value.category
    items = value.items.filter { $0.category == category }
    query = value.query ?? ""
    notice.setTitle(value.notice, for: .normal)
    notice.isHidden = value.notice?.isEmpty != false
    noticeHeight.constant = notice.isHidden ? 0 : 44
    render()
  }

  private func render() {
    rows = items.filter { item in
      if category == "file" && query.isEmpty { return (item.path as NSString).deletingLastPathComponent == path }
      return item.matches(query)
    }
    location.setImage(path.isEmpty ? nil : UIImage(systemName: "chevron.left"), for: .normal)
    location.setTitle(path.isEmpty ? LodyStrings.text("native.chat.mention." + (ChatMentionItem.labels[category] ?? category)) : "  " + path, for: .normal)
    location.isEnabled = !path.isEmpty
    location.isHidden = path.isEmpty
    breadcrumbHeight.constant = path.isEmpty ? 0 : 44
    list.contentInset.top = breadcrumbHeight.constant + noticeHeight.constant
    list.verticalScrollIndicatorInsets.top = list.contentInset.top
    useDirectory.isHidden = path.isEmpty
    useDirectory.setTitle(LodyStrings.text("native.chat.mention.directory", ["name": (path as NSString).lastPathComponent]), for: .normal)
    empty.isHidden = !rows.isEmpty
    list.reloadData()
  }

  @objc private func retry() { onRetry([:]) }
  @objc private func back() {
    path = (path as NSString).deletingLastPathComponent
    query = ""
    onQueryReset([:])
    render()
  }
  @objc private func pickDirectory() { onPick(["path": path]) }
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { rows.count }
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let item = rows[indexPath.item]
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "item", for: indexPath) as! UICollectionViewListCell
    cell.contentConfiguration = item.content
    cell.accessibilityIdentifier = "mention-picker-item:" + item.path
    cell.accessories = item.kind == "directory" ? [.disclosureIndicator()] : []
    return cell
  }
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: true)
    let item = rows[indexPath.item]
    if item.kind == "directory" {
      path = item.path
      query = ""
      onQueryReset([:])
      render()
    } else { onPick(["path": item.path]) }
  }
}
