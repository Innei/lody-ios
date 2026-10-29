import AppKit
import LodyData

@MainActor
enum MacFixtures {
  static var listState: SessionListState {
    let catalog = SessionCatalog(
      projects: [
        SessionProject(id: "p-ios", name: "lody-ios", rootPath: "~/git/lody-ios"),
        SessionProject(id: "p-web", name: "lody-web", rootPath: "~/git/lody-web"),
        SessionProject(id: "p-docs", name: "handbook", rootPath: "~/git/handbook"),
      ],
      sessions: [
        SessionItem(id: "s-mac", title: "Build the AppKit sidebar", status: "running", projectId: "p-ios", lastMessageAt: 1_800_000_090, branchName: "mac-client", machineId: "m-studio", agentType: "claude"),
        SessionItem(id: "s-review", title: "Review transcript projection", projectId: "p-ios", lastMessageAt: 1_800_000_060, lastReadAt: 1_800_000_000, machineId: "m-studio", agentType: "codex"),
        SessionItem(id: "s-tabs", title: "Native window tabs", projectId: "p-ios", lastMessageAt: 1_800_000_030, lastReadAt: 1_800_000_030, machineId: "m-studio"),
        SessionItem(id: "s-landing", title: "Landing page copy", projectId: "p-web", lastMessageAt: 1_800_000_080, awaitingUserSince: 1_800_000_079, machineId: "m-mini", agentType: "claude"),
        SessionItem(id: "s-deploy", title: "Deploy preview", projectId: "p-web", lastMessageAt: 1_800_000_010, lastReadAt: 1_800_000_010, machineId: "m-mini"),
        SessionItem(id: "s-plan", title: "Q4 roadmap", pinned: true, projectId: "p-docs", lastMessageAt: 1_800_000_050, lastReadAt: 1_800_000_050, machineId: "m-studio"),
        SessionItem(id: "s-old", title: "Archived spike", archived: true, projectId: "p-ios", lastMessageAt: 1_800_000_099),
      ],
      machineIds: ["m-studio", "m-mini"],
      machineNames: ["m-studio": "Mac Studio", "m-mini": "Mac mini"]
    )
    var state = SessionListState(userId: "u-fixture", workspaceId: "w-fixture", catalog: catalog)
    state.presence = SettingsMachinePresence(state: "live", onlineMachineIds: ["m-studio", "m-mini"])
    state.workspaces = [AuthWorkspace(id: "w-fixture", name: "Innei Lab", slug: "innei", image: nil)]
    return state
  }

  static var environment: MacEnvironment {
    let sessions = MacSessionsSource.fixture(listState)
    return MacEnvironment(
      sessions: sessions,
      pane: { MacSessionSummaryPane(sessionId: $0, sessions: sessions) },
      requiresAccount: false,
      windowIdentifier: "catalog-scene",
      titlePrefix: "Catalog · "
    )
  }

  static func workspaceWindow(sessionId: String?) -> [NSWindow] {
    let controller = MainWindowController(environment: environment, sessionId: sessionId)
    return controller.window.map { [$0] } ?? []
  }

  static func tabbedWindows() -> [NSWindow] {
    let first = MainWindowController(environment: environment, sessionId: "s-mac")
    let second = first.addTab(sessionId: "s-landing")
    let third = first.addTab(sessionId: "s-plan")
    return [first, second, third].compactMap(\.window)
  }
}
