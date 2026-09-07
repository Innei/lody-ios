import Photos
import UIKit

private final class ChatPhotoCell: UICollectionViewCell {
  let image = UIImageView()
  private let badge = UIImageView()
  var assetID: String?
  override init(frame: CGRect) {
    super.init(frame: frame)
    image.contentMode = .scaleAspectFill
    image.clipsToBounds = true
    image.backgroundColor = .tertiarySystemFill
    image.layer.cornerRadius = 6
    image.layer.cornerCurve = .continuous
    badge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
    badge.layer.shadowRadius = 2
    badge.layer.shadowOffset = .zero
    contentView.addSubview(image)
    contentView.addSubview(badge)
    image.translatesAutoresizingMaskIntoConstraints = false
    badge.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      image.topAnchor.constraint(equalTo: contentView.topAnchor), image.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      image.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), image.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      badge.trailingAnchor.constraint(equalTo: image.trailingAnchor, constant: -5),
      badge.bottomAnchor.constraint(equalTo: image.bottomAnchor, constant: -5),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .image
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func mark(selected: Bool) {
    badge.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
    badge.tintColor = selected ? .systemBlue : .white.withAlphaComponent(0.9)
    badge.layer.shadowOpacity = selected ? 0 : 0.3
    image.layer.borderWidth = selected ? 2 : 0
    image.layer.borderColor = UIColor.systemBlue.resolvedColor(with: traitCollection).cgColor
    accessibilityValue = selected ? LodyStrings.text("native.chat.attachment.selected") : nil
  }
}

final class ChatAttachmentSheet: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  var onPick: (([ChatAttachment]) -> Void)?
  private let grid: UICollectionView
  private let status = UIStackView()
  private let statusLabel = UILabel()
  private let statusAction = UIButton(configuration: .filled())
  private let confirm = UIButton(configuration: .filled())
  private let manage = UIButton(configuration: .plain())
  private let column = UIStackView()
  private var assets: PHFetchResult<PHAsset>?
  private var selection: [String] = []
  private let images = PHImageManager.default()

  init() {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 3
    layout.minimumInteritemSpacing = 3
    grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .pageSheet
    sheetPresentationController?.detents = [.medium(), .large()]
    sheetPresentationController?.prefersGrabberVisible = true
    sheetPresentationController?.prefersScrollingExpandsWhenScrolledToEdge = false
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    grid.backgroundColor = .clear
    grid.dataSource = self
    grid.delegate = self
    grid.alwaysBounceVertical = true
    grid.register(ChatPhotoCell.self, forCellWithReuseIdentifier: "photo")
    statusLabel.numberOfLines = 0
    statusLabel.textAlignment = .center
    statusLabel.font = .systemFont(ofSize: 15)
    statusLabel.textColor = .secondaryLabel
    statusAction.addAction(UIAction { [weak self] _ in self?.runStatusAction() }, for: .touchUpInside)
    status.axis = .vertical
    status.spacing = 16
    status.alignment = .center
    status.addArrangedSubview(statusLabel)
    status.addArrangedSubview(statusAction)
    manage.setTitle(LodyStrings.text("native.chat.attachment.managePhotos"), for: .normal)
    manage.isHidden = true
    manage.addAction(UIAction { [weak self] _ in self?.manageLimited() }, for: .touchUpInside)
    confirm.configuration?.cornerStyle = .capsule
    confirm.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28)
    confirm.alpha = 0
    confirm.addAction(UIAction { [weak self] _ in self?.commit() }, for: .touchUpInside)
    column.axis = .vertical
    column.spacing = 12
    for item in [grid, manage] { column.addArrangedSubview(item) }
    for item in [column, status, confirm] {
      item.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(item)
    }
    NSLayoutConstraint.activate([
      column.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
      column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      status.centerYAnchor.constraint(equalTo: grid.centerYAnchor),
      status.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
      status.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
      confirm.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      confirm.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
      confirm.heightAnchor.constraint(equalToConstant: 50),
    ])
    refresh()
  }

  private func refresh() {
    let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    manage.isHidden = auth != .limited
    switch auth {
    case .authorized, .limited:
      let options = PHFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.fetchLimit = 60
      assets = PHAsset.fetchAssets(with: .image, options: options)
      status.isHidden = true
    case .notDetermined:
      assets = nil
      status.isHidden = false
      statusLabel.text = LodyStrings.text("native.chat.attachment.limitedAccess")
      statusAction.setTitle(LodyStrings.text("native.chat.attachment.allowAccess"), for: .normal)
    default:
      assets = nil
      status.isHidden = false
      statusLabel.text = LodyStrings.text("native.chat.attachment.accessDenied")
      statusAction.setTitle(LodyStrings.text("native.chat.attachment.openSettings"), for: .normal)
    }
    grid.reloadData()
  }

  private func runStatusAction() {
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
        DispatchQueue.main.async { self?.refresh() }
      }
    default:
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(url)
    }
  }

  private func manageLimited() {
    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self) { [weak self] _ in
      DispatchQueue.main.async { self?.refresh() }
    }
  }

  private func finish(_ picked: [ChatAttachment]) {
    dismiss(animated: true) { [onPick] in onPick?(picked) }
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    assets?.count ?? 0
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: indexPath) as! ChatPhotoCell
    guard let asset = assets?.object(at: indexPath.item) else { return cell }
    cell.assetID = asset.localIdentifier
    cell.mark(selected: selection.contains(asset.localIdentifier))
    cell.accessibilityLabel = LodyStrings.text("native.chat.attachment.photoIndex", ["index": indexPath.item + 1])
    let side = thumbnailSide(in: collectionView) * (view.window?.screen.scale ?? 2)
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .opportunistic
    images.requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options) { image, _ in
      guard cell.assetID == asset.localIdentifier else { return }
      cell.image.image = image
    }
    return cell
  }

  private func thumbnailSide(in collectionView: UICollectionView) -> CGFloat {
    max(1, ((collectionView.bounds.width - 6) / 3).rounded(.down))
  }

  func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    let side = thumbnailSide(in: collectionView)
    return CGSize(width: side, height: side)
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let asset = assets?.object(at: indexPath.item) else { return }
    if let index = selection.firstIndex(of: asset.localIdentifier) { selection.remove(at: index) }
    else if selection.count < 10 { selection.append(asset.localIdentifier) }
    else { return }
    (collectionView.cellForItem(at: indexPath) as? ChatPhotoCell)?.mark(selected: selection.contains(asset.localIdentifier))
    UISelectionFeedbackGenerator().selectionChanged()
    updateConfirm()
  }

  private func updateConfirm() {
    let visible = !selection.isEmpty
    if visible {
      confirm.setTitle(
        LodyStrings.plural("native.chat.attachment.addCount", selection.count),
        for: .normal
      )
    }
    grid.contentInset.bottom = visible ? 74 : 0
    UIView.animate(withDuration: 0.2) {
      self.confirm.alpha = visible ? 1 : 0
      self.confirm.transform = visible ? .identity : CGAffineTransform(scaleX: 0.9, y: 0.9)
    }
  }

  private func commit() {
    let picked = PHAsset.fetchAssets(withLocalIdentifiers: selection, options: nil)
    guard picked.count > 0 else { return }
    confirm.isEnabled = false
    confirm.configuration?.showsActivityIndicator = true
    let group = DispatchGroup()
    let lock = NSLock()
    var attachments: [ChatAttachment] = []
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.version = .current
    picked.enumerateObjects { asset, _, _ in
      group.enter()
      self.images.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
        defer { group.leave() }
        let name = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "\(UUID().uuidString).jpg"
        guard let data, let url = ChatAttachment.store(data, name: name) else { return }
        lock.lock()
        attachments.append(ChatAttachment(id: asset.localIdentifier, name: name, url: url, isImage: true))
        lock.unlock()
      }
    }
    group.notify(queue: .main) { [weak self] in self?.finish(attachments) }
  }
}
