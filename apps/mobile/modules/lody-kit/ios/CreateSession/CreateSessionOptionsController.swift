import UIKit

/// All advertised configuration options, including permission, collaboration and presets.
@MainActor
final class CreateSessionOptionsController: UICollectionViewController {
  private var form: CreateSessionForm
  private var capability: [String: Any] { form.capability }
  private var choice: [String: Any] { get { form.choice } set { form.choice = newValue } }
  private let onChange: (CreateSessionForm) -> Void
  private var options: [(id: String, name: String, values: [(String, String)], config: Bool)] = []
  init(form: CreateSessionForm, onChange: @escaping (CreateSessionForm) -> Void) {
    self.form = form; self.onChange = onChange
    super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: .init(appearance: .insetGrouped)))
    title = LodyStrings.text("native.create.modelOptions")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidLoad() {
    super.viewDidLoad()
    _ = registration // UIKit forbids first registration from cellForItemAt.
    LodyScrollEdges.bind(collectionView, to: self); LodyScrollEdges.navigation(collectionView); reload()
  }
  private func reload() {
    options = []
    for (id, title, key) in [("modelId", LodyStrings.text("native.create.model"), "models"), ("modeId", LodyStrings.text("native.create.permissions"), "modes")] {
      let values = (capability[key] as? [[String: Any]] ?? []).map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "") }
      if !values.isEmpty { options.append((id, title, [("", LodyStrings.text("native.create.default"))] + values, false)) }
    }
    let efforts = form.efforts
    if !efforts.isEmpty { options.append(("effort", LodyStrings.text("native.create.effort"), [("", LodyStrings.text("native.create.default"))] + efforts.map { ($0, $0) }, false)) }
    for option in form.configOptions.filter(CreateSessionForm.extraOption) {
      guard let id = option["id"] as? String, let name = option["name"] as? String else { continue }
      let values: [(String, String)]
      if option["type"] as? String == "boolean" { values = [("true", LodyStrings.text("native.create.on")), ("false", LodyStrings.text("native.create.off"))] }
      else { values = (option["options"] as? [[String: Any]] ?? []).map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "") } }
      options.append((id, name, [("", LodyStrings.text("native.create.default"))] + values, true))
    }
    collectionView.reloadData()
  }
  private func selected(_ index: Int) -> String {
    let option = options[index]
    let values = choice["configOptionValues"] as? [String: Any] ?? [:]
    let value = option.config ? values[option.id] : choice[option.id]
    if let bool = value as? Bool { return bool ? "true" : "false" }
    return value as? String ?? ""
  }
  private lazy var registration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { [weak self] cell, _, index in
    guard let self else { return }
    var content = UIListContentConfiguration.valueCell(); content.text = self.options[index].name
    content.secondaryText = self.options[index].values.first { $0.0 == self.selected(index) }?.1 ?? LodyStrings.text("native.create.default")
    cell.contentConfiguration = content; cell.accessories = [.disclosureIndicator()]
    cell.accessibilityIdentifier = "option-" + self.options[index].id
  }
  override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { options.count }
  override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: indexPath.item)
  }
  override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    let option = options[indexPath.item]
    let picker = CreateSessionPicker(title: option.name, items: option.values, selected: selected(indexPath.item)) { [weak self] value in
      guard let self else { return }
      if option.config {
        var values = self.choice["configOptionValues"] as? [String: Any] ?? [:]
        let boolean = (self.capability["configOptions"] as? [[String: Any]] ?? []).first { $0["id"] as? String == option.id }?["type"] as? String == "boolean"
        if value.isEmpty { values[option.id] = nil }
        else if boolean { values[option.id] = value == "true" }
        else { values[option.id] = value }
        self.choice["configOptionValues"] = values
      } else {
        if option.id == "modelId" { self.form.selectModel(value) }
        else { self.choice[option.id] = value.isEmpty ? nil : value }
      }
      self.form.remember(); self.onChange(self.form); self.reload()
    }
    navigationController?.pushViewController(picker, animated: true)
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    guard let selected = collectionView.indexPathsForSelectedItems?.first else { return }
    transitionCoordinator?.animate(alongsideTransition: { _ in self.collectionView.deselectItem(at: selected, animated: animated) }) { context in
      if context.isCancelled { self.collectionView.selectItem(at: selected, animated: false, scrollPosition: []) }
    }
  }
}
