import Foundation

extension LodyListRow {
  static func item(
    _ id: String, _ title: String, subtitle: String = "", value: String = "", image: String = "",
    imageAsset: String = "", action: Bool = true, disclosure: Bool = false, navigates: Bool = false,
    selected: Bool = false, accessibilityValue: String = "", toggle: Bool? = nil, subtitleMono: Bool = false
  ) -> LodyListRow {
    var row = LodyListRow()
    row.id = id
    row.title = title
    row.subtitle = subtitle
    row.value = value
    row.image = image
    row.imageAsset = imageAsset
    row.action = action
    row.disclosure = disclosure
    row.navigates = navigates
    row.selected = selected
    row.accessibilityValue = accessibilityValue
    row.toggle = toggle
    row.subtitleMono = subtitleMono
    return row
  }
}

extension LodyListSection {
  static func group(_ id: String, header: String = "", footer: String = "", _ rows: [LodyListRow]) -> LodyListSection {
    var section = LodyListSection()
    section.id = id
    section.header = header
    section.footer = footer
    section.rows = rows
    return section
  }
}

enum CreateSessionSections {
  private static func text(_ key: String) -> String { LodyStrings.text(key) }

  private static func pickTitle(_ loading: Bool, _ idle: String) -> String {
    loading ? text("common.reading") : idle
  }

  static func root(_ form: CreateSessionForm, page: CreateSessionPage) -> [LodyListSection] {
    let machine = page.machine
    let capability = page.capability
    let machineRow = LodyListRow.item(
      "machine", machine?.name ?? pickTitle(page.loading, text("create.row.selectMachine")),
      subtitle: text("create.label.machine"), image: "desktopcomputer", disclosure: true, navigates: true)
    let modelRow = LodyListRow.item(
      "model", capability.map { CreateModelOptions.summary($0, page.choice) } ?? text("model.default"),
      subtitle: text("create.label.model"), image: "cpu",
      action: capability != nil, disclosure: capability != nil, navigates: capability != nil)
    let agent = page.agent
    var footer = text(form.deferUnresolved ? "native.share.deferred" : "create.machineConfig.retry")
    if page.loading { footer = text("create.machineConfig.loading") }
    else if agent != nil { footer = text("create.machineConfig.ready") }
    let agentSection = LodyListSection.group("agent", footer: footer, [
      .item(
        "agent", agent?.name ?? pickTitle(page.loading, text("create.row.selectAgent")),
        subtitle: text("create.label.agent"), image: "sparkles",
        imageAsset: LodyAgentIcon.asset(modelId: agent?.agentType, name: nil) ?? "",
        disclosure: true, navigates: true),
      modelRow,
    ])
    if page.chat { return [.group("machine", [machineRow]), agentSection] }

    let project = form.projects.first { $0.id == page.projectId }
    let subtitle = page.github ? "GitHub" : [
      form.machineNames[project?.machineId ?? ""] ?? machine?.name ?? project?.machineId,
      project?.rootPath,
    ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    var projectRows: [LodyListRow] = [.item(
      "project", project?.name ?? text("create.row.selectProject"), subtitle: subtitle,
      image: page.github ? "" : "folder", imageAsset: page.github ? "lody-mark-github" : "",
      disclosure: true, navigates: true)]
    if page.github {
      let branch = page.branch.isEmpty ? text("create.branch.placeholder") : page.branch
      projectRows.append(.item(
        "branch", text("create.branch.label"), value: branch, image: "arrow.triangle.branch",
        disclosure: true, accessibilityValue: branch))
    }
    var sections: [LodyListSection] = [.group("project", projectRows)]
    if page.github { sections.append(.group("machine", [machineRow])) }
    sections.append(agentSection)
    return sections
  }

  static func choices(
    _ options: [(id: String, title: String, subtitle: String)], header: String, selected: String?
  ) -> [LodyListSection] {
    [.group("options", header: header, options.map { option in
      .item(
        option.id, option.title, subtitle: option.subtitle, selected: option.id == selected,
        accessibilityValue: option.id == selected ? text("settings.history.selected") : "")
    })]
  }
}

enum CreateProjectPicker {
  static func isGithub(_ id: String) -> Bool { id.hasPrefix("github:") }

  static func filter(_ projects: [CreateProject], _ query: String) -> [CreateProject] {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !term.isEmpty else { return projects }
    return projects.filter { [$0.name, $0.rootPath, $0.id].joined(separator: " ").lowercased().contains(term) }
  }

  static func row(_ project: CreateProject, machineNames: [String: String], selected: String) -> LodyListRow {
    let github = isGithub(project.id)
    return .item(
      project.id, project.name,
      subtitle: [machineNames[project.machineId] ?? project.machineId, project.rootPath]
        .filter { !$0.isEmpty }.joined(separator: " · "),
      image: github ? "" : "folder", imageAsset: github ? "lody-mark-github" : "",
      selected: project.id == selected, subtitleMono: !project.rootPath.isEmpty)
  }

  static func githubStatusRows(loaded: Bool, failed: Bool, empty: Bool) -> [LodyListRow] {
    if !loaded {
      return [.item(
        "github-retry", LodyStrings.text(failed ? "projectPicker.githubFailed" : "common.reading"),
        image: failed ? "arrow.clockwise" : "", action: failed)]
    }
    if empty { return [.item("github-empty", LodyStrings.text("projectPicker.githubEmpty"), action: false)] }
    return []
  }
}
