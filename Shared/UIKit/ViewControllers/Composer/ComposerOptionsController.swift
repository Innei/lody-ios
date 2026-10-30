import UIKit

final class ComposerOptionsController: UIViewController, UIPopoverPresentationControllerDelegate {
  var onModel: ((String) -> Void)?
  var onEffort: ((String) -> Void)?
  var onFast: ((Bool) -> Void)?
  private var options = ChatComposerOptions()
  private let model = UIButton(type: .system)
  private let fast = UIButton(type: .system)
  private let slider = ChatEffortSlider()
  private lazy var modelLeading = model.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24)
  private lazy var modelTrailing = model.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .secondarySystemGroupedBackground
    fast.accessibilityIdentifier = "composer-fast"
    fast.accessibilityLabel = String(localized: "native.chat.composer.fast", bundle: .lody)
    fast.addTarget(self, action: #selector(toggleFast), for: .touchUpInside)
    model.showsMenuAsPrimaryAction = true
    model.accessibilityIdentifier = "composer-model-menu"
    slider.accessibilityLabel = String(localized: "native.chat.composer.effort", bundle: .lody)
    slider.accessibilityIdentifier = "composer-effort-slider"
    slider.addTarget(self, action: #selector(changeEffort), for: .valueChanged)
    for child in [model, slider, fast] {
      child.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(child)
    }
    NSLayoutConstraint.activate([
      fast.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      fast.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      fast.widthAnchor.constraint(equalToConstant: 44),
      fast.heightAnchor.constraint(equalToConstant: 44),
      modelLeading,
      modelTrailing,
      model.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      model.heightAnchor.constraint(equalToConstant: 56),
      slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      slider.topAnchor.constraint(equalTo: model.bottomAnchor, constant: 8),
      slider.heightAnchor.constraint(equalToConstant: 44),
    ])
  }

  func render(_ options: ChatComposerOptions) {
    self.options = options
    fast.isHidden = options.fast == nil
    modelLeading.constant = options.fast == nil ? 24 : 56
    modelTrailing.constant = -modelLeading.constant
    let enabled = options.fast == true
    var fastConfiguration = UIButton.Configuration.plain()
    fastConfiguration.image = UIImage(systemName: enabled ? "bolt.fill" : "bolt")
    fastConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    fastConfiguration.baseForegroundColor = enabled ? .lodyAccent : .secondaryLabel
    fastConfiguration.contentInsets = .zero
    if fast.configuration?.image != nil {
      fastConfiguration.symbolContentTransition = .init(.replace.byLayer)
    }
    fast.configuration = fastConfiguration
    fast.accessibilityTraits = enabled ? [.button, .selected] : [.button]
    fast.accessibilityValue = String(localized: String.LocalizationValue(enabled ? "native.chat.composer.fastOn" : "native.chat.composer.fastOff"), bundle: .lody)
    preferredContentSize = CGSize(width: 320, height: options.efforts.isEmpty ? 76 : 132)
    var configuration = UIButton.Configuration.plain()
    configuration.baseForegroundColor = options.effort.lowercased() == "ultra" ? ChatEffortSlider.ultraColor : .lodyAccent
    configuration.title = options.effortTitle + " ›"
    configuration.subtitle = options.modelTitle
    configuration.titleAlignment = .center
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.subtitleLineBreakMode = .byTruncatingTail
    configuration.titleTextAttributesTransformer = .init { attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .headline)
      return attributes
    }
    configuration.subtitleTextAttributesTransformer = .init { attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .subheadline)
      attributes.foregroundColor = .secondaryLabel
      return attributes
    }
    model.configuration = configuration
    model.accessibilityLabel = String.localizedStringWithFormat(String(localized: "native.chat.composer.modelPicker", bundle: .lody), String(describing: options.effortTitle), String(describing: options.modelTitle))
    model.menu = UIMenu(children: [
      UIAction(title: String(localized: "native.chat.composer.defaultModel", bundle: .lody), state: options.modelId.isEmpty ? .on : .off) { [weak self] _ in self?.onModel?("") },
    ] + options.models.map { option in
      UIAction(title: option.title, state: option.id == options.modelId ? .on : .off) { [weak self] _ in self?.onModel?(option.id) }
    })
    let efforts = options.orderedEfforts
    slider.isHidden = efforts.isEmpty
    slider.steps = max(1, efforts.count)
    slider.value = Float(efforts.firstIndex { $0.id == options.effort }.map { $0 + 1 } ?? 0) / Float(max(1, efforts.count))
    slider.accessibilityValue = options.effortTitle
    slider.isFast = options.fast == true
    slider.isUltra = options.effort.lowercased() == "ultra" && !efforts.isEmpty
  }

  @objc private func toggleFast() {
    guard let current = options.fast else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    onFast?(!current)
  }

  @objc private func changeEffort() {
    let efforts = options.orderedEfforts
    let index = min(efforts.count, max(0, Int((slider.value * Float(efforts.count)).rounded())))
    slider.value = Float(index) / Float(max(1, efforts.count))
    let effort = index == 0 ? "" : efforts[index - 1].id
    guard effort != options.effort else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    onEffort?(effort)
  }

  func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
}
