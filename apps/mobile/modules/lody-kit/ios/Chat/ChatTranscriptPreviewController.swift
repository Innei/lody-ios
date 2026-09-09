import UIKit

final class ChatTranscriptPreviewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  private let sessionId: String
  private let sessionTitle: String
  private let userId: String
  private let workspaceId: String
  private let collection: UICollectionView
  private let empty = UILabel()
  private var rows: [ChatRow] = []

  init(sessionId: String, title: String, userId: String, workspaceId: String) {
    self.sessionId = sessionId
    self.sessionTitle = title
    self.userId = userId
    self.workspaceId = workspaceId
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 0
    layout.minimumInteritemSpacing = 0
    layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    view.accessibilityIdentifier = "session-preview"
    view.accessibilityLabel = sessionTitle
    collection.backgroundColor = .systemBackground
    collection.dataSource = self
    collection.delegate = self
    collection.isScrollEnabled = true
    collection.alwaysBounceVertical = true
    collection.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "message")
    empty.numberOfLines = 0
    empty.textAlignment = .center
    empty.font = .preferredFont(forTextStyle: .subheadline)
    empty.textColor = .secondaryLabel
    empty.text = LodyStrings.text("native.chat.empty.loading")
    empty.adjustsFontForContentSizeCategory = true
    collection.backgroundView = empty
    view.addSubview(collection)
    collection.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      collection.topAnchor.constraint(equalTo: view.topAnchor),
      collection.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      collection.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    preferredContentSize = CGSize(width: 320, height: 220)
    loadCache()
  }

  private func loadCache() {
    let userId = userId
    let workspaceId = workspaceId
    let sessionId = sessionId
    LocalStore.queue.async { [weak self] in
      var cache = ""
      if let data = try? JSONSerialization.data(
        withJSONObject: [userId, workspaceId, sessionId],
        options: [.withoutEscapingSlashes]
      ), let suffix = String(data: data, encoding: .utf8) {
        cache = (try? LocalStore.shared.read("session:" + suffix)) ?? ""
      }
      let rows = ChatTranscript.previewRows(from: cache)
      DispatchQueue.main.async {
        self?.apply(rows)
      }
    }
  }

  private func apply(_ rows: [ChatRow]) {
    self.rows = rows
    empty.text = rows.isEmpty ? LodyStrings.text("native.chat.preview.empty") : nil
    empty.isHidden = !rows.isEmpty
    collection.reloadData()
    collection.layoutIfNeeded()
    let height = min(420, max(160, collection.contentSize.height + 16))
    preferredContentSize = CGSize(width: 320, height: height)
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    rows.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "message", for: indexPath) as! UICollectionViewListCell
    let row = rows[indexPath.item]
    let secondary = row.kind == "thought" || row.kind == "summary" || row.kind == "duration"
    var content = UIListContentConfiguration.cell()
    content.text = row.text
    content.textProperties.font = .preferredFont(forTextStyle: row.kind == "summary" ? .footnote : .body)
    content.textProperties.color = secondary ? .secondaryLabel : .label
    content.textProperties.numberOfLines = 0
    if !row.symbol.isEmpty {
      content.image = UIImage(systemName: row.symbol)
      content.imageProperties.tintColor = row.attention ? .systemOrange : .secondaryLabel
    }
    cell.contentConfiguration = content
    cell.backgroundConfiguration = .clear()
    cell.accessibilityIdentifier = row.id
    cell.isUserInteractionEnabled = false
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    let row = rows[indexPath.item]
    let width = collectionView.bounds.width
    let inset = (collectionViewLayout as? UICollectionViewFlowLayout)?.sectionInset ?? .zero
    let textWidth = max(1, width - inset.left - inset.right - 36)
    let font = UIFont.preferredFont(forTextStyle: row.kind == "summary" ? .footnote : .body)
    let height = (row.text as NSString).boundingRect(
      with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font],
      context: nil
    ).height
    return CGSize(width: max(1, width - inset.left - inset.right), height: max(36, ceil(height) + 16))
  }
}
