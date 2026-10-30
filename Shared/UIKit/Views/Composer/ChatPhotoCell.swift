#if LODY_SHARE_EXTENSION
import AVFoundation
import Photos
import UIKit

final class ChatPhotoCell: UICollectionViewCell {
  let image = UIImageView()
  private let badge = UIImageView()
  private let videoMark = UIImageView(image: UIImage(systemName: "video.fill"))
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
    videoMark.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
    videoMark.tintColor = .white
    videoMark.layer.shadowOpacity = 0.45
    videoMark.layer.shadowRadius = 2
    videoMark.layer.shadowOffset = .zero
    videoMark.isHidden = true
    contentView.addSubview(image)
    contentView.addSubview(videoMark)
    contentView.addSubview(badge)
    image.translatesAutoresizingMaskIntoConstraints = false
    videoMark.translatesAutoresizingMaskIntoConstraints = false
    badge.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      image.topAnchor.constraint(equalTo: contentView.topAnchor), image.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      image.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), image.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      videoMark.leadingAnchor.constraint(equalTo: image.leadingAnchor, constant: 6),
      videoMark.bottomAnchor.constraint(equalTo: image.bottomAnchor, constant: -6),
      badge.trailingAnchor.constraint(equalTo: image.trailingAnchor, constant: -5),
      badge.bottomAnchor.constraint(equalTo: image.bottomAnchor, constant: -5),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .image
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func mark(selected: Bool, video: Bool = false) {
    badge.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
    badge.tintColor = selected ? .lodyAccent : .white.withAlphaComponent(0.9)
    badge.layer.shadowOpacity = selected ? 0 : 0.3
    image.layer.borderWidth = selected ? 2 : 0
    image.layer.borderColor = UIColor.lodyAccent.resolvedColor(with: traitCollection).cgColor
    videoMark.isHidden = !video
    accessibilityValue = selected ? String(localized: "native.chat.attachment.selected", bundle: .lody) : nil
  }
}
#endif
