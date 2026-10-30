import AppKit
import ChatAppKit
import ChatKitCore

@MainActor
final class MacTranscriptImageView: NSView {
  static let maxWidth: CGFloat = 320
  let photo = NSImageView()
  let media: CKMediaRef
  var onPreview: ((CKMediaRef) -> Void)?
  private let provider: CKMediaProvider?
  private let ratio: CGFloat
  private var height: NSLayoutConstraint!
  private var task: Task<Void, Never>?
  private var requested: CGSize?

  init(media: CKMediaRef, name: String, aspect: Double?, provider: CKMediaProvider?) {
    self.media = media
    self.provider = provider
    ratio = CGFloat(max(0.4, min(aspect ?? 1.6, 3)))
    super.init(frame: .zero)
    photo.imageScaling = .scaleProportionallyUpOrDown
    photo.wantsLayer = true
    photo.layer?.cornerRadius = 10
    photo.layer?.masksToBounds = true
    photo.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    photo.setAccessibilityElement(false)
    addSubview(photo)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(name)
    setAccessibilityIdentifier("transcript-image")
    height = heightAnchor.constraint(equalToConstant: (Self.maxWidth / ratio).rounded())
    height.priority = .init(999)
    height.isActive = true
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit { task?.cancel() }

  override func layout() {
    super.layout()
    let width = min(Self.maxWidth, bounds.width)
    let next = (width / ratio).rounded()
    if abs(height.constant - next) > 0.5 { height.constant = next }
    photo.frame = NSRect(x: 0, y: bounds.height - next, width: width, height: next)
    load()
  }

  override func mouseUp(with event: NSEvent) {
    guard photo.frame.contains(convert(event.locationInWindow, from: nil)) else { return }
    onPreview?(media)
  }

  override func accessibilityPerformPress() -> Bool {
    onPreview?(media)
    return true
  }

  private func load() {
    guard let provider, let window, photo.bounds.width > 1 else { return }
    let size = photo.bounds.size
    let pixels = CGSize(width: size.width * window.backingScaleFactor, height: size.height * window.backingScaleFactor)
    guard requested != pixels else { return }
    requested = pixels
    task?.cancel()
    let media = media
    task = Task { [weak self] in
      guard let image = try? await provider.image(for: media, pixelSize: pixels), !Task.isCancelled else { return }
      self?.photo.image = NSImage(cgImage: image, size: size)
    }
  }
}

@MainActor
final class MacTranscriptAttachmentsView: NSView {
  let strip = CKAttachmentStripView()
  var onPreview: ((CKMediaRef) -> Void)?
  private var files: [MacAttachmentItem]
  private var thumbnails: [String: CGImage] = [:]
  private var tasks: [Task<Void, Never>] = []

  init(files: [MacAttachmentItem], provider: CKMediaProvider?) {
    self.files = files
    super.init(frame: .zero)
    strip.trailing = true
    strip.labels = .init(
      remove: String(localized: "mac.attachments.remove", bundle: .lodyMac),
      failed: String(localized: "mac.attachments.failed", bundle: .lodyMac),
      uploading: { String(localized: "mac.attachments.uploading \($0)", bundle: .lodyMac) }
    )
    strip.onPreview = { [weak self] in
      guard let media = $0.media else { return }
      self?.onPreview?(media)
    }
    strip.setAccessibilityIdentifier("transcript-attachments")
    strip.translatesAutoresizingMaskIntoConstraints = false
    addSubview(strip)
    NSLayoutConstraint.activate([
      strip.topAnchor.constraint(equalTo: topAnchor),
      strip.bottomAnchor.constraint(equalTo: bottomAnchor),
      strip.leadingAnchor.constraint(equalTo: leadingAnchor),
      strip.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    render()
    guard let provider else { return }
    for file in files where file.image {
      let media = file.media
      tasks.append(Task { [weak self] in
        guard let image = try? await provider.image(for: media, pixelSize: CGSize(width: 56, height: 56)), !Task.isCancelled else { return }
        self?.thumbnails[file.id] = image
        self?.render()
      })
    }
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit { tasks.forEach { $0.cancel() } }

  private func render() {
    strip.render(files.map { file in
      var attachment = file.attachment
      attachment.thumbnail = thumbnails[file.id]
      return attachment
    })
  }
}
