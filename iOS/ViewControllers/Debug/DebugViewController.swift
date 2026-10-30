import LodyCore
import UIKit

final class DebugViewController: UIViewController {
  private static let groups: [(id: String, header: String, rows: [(String, String, String)])] = [
    ("ui", "界面验收", [
      ("create-recovery", "Device recovery verification", "desktopcomputer"),
      ("pull-request-preview", "GitHub PR / CI 预览", "arrow.triangle.pull"),
      ("project-picker-preview", "选择项目验收", "folder"),
      ("notification-preview", "通知权限验收", "bell"),
      ("live-activity-preview", "Live Activity 演示", "sparkles"),
      ("push-subscription-verify", "验证 OneSignal 订阅", "bell.badge"),
      ("permission-preview", "权限验收", "hand.raised"),
      ("onboarding-preview", "登录引导验收", "hand.wave"),
      ("project-history-preview", "项目会话同步验收", "arrow.triangle.2.circlepath"),
      ("directory-preview", "Folder browser", "folder"),
      ("project-preview", "Project page", "folder.badge.gearshape"),
      ("activity-preview", "Activity page", "bolt.horizontal"),
      ("settings-preview", "远程设置验收", "gear"),
      ("settings-baseline-live", "Settings baseline", "gearshape.2"),
      ("ai-usage-preview", "AI usage", "chart.bar"),
      ("mcp-settings-preview", "MCP 设置验收", "server.rack"),
      ("memory-preview", "Memory acceptance", "brain"),
      ("published-shares-preview", "Published shares acceptance", "link"),
      ("memory-states-preview", "Memory states", "brain"),
      ("agent-roles-preview", "Agent 角色验收", "person.crop.square"),
      ("archived-sessions-preview", "Archived sessions", "archivebox"),
      ("session-preview-live", "Session", "bubble.left"),
      ("machine-settings-preview", "机器设置验收", "desktopcomputer"),
      ("preferences-preview", "偏好设置验收", "slider.horizontal.3"),
      ("diagnostics-preview", "Diagnostics", "waveform.path.ecg"),
      ("appearance-preview", "外观验收", "circle.lefthalf.filled"),
      ("queued-message-behavior-preview", "排队消息行为验收", "arrow.uturn.forward"),
      ("model-memory", "Model memory verification", "brain"),
      ("create-parity", "Create parity verification", "square.on.square"),
    ]),
    ("chat", "聊天与输入", [
      ("item-detail-preview", "Item details", "doc.text.magnifyingglass"),
      ("edit-message-preview", "Message editing", "pencil"),
      ("file-diff-preview", "Diff", "plus.forwardslash.minus"),
      ("workspace-changes-preview", "Workspace changes", "arrow.triangle.branch"),
      ("file-content-preview", "File content", "doc"),
      ("agent-error-preview", "Agent 错误预览", "exclamationmark.circle"),
    ]),
    ("send", "发送", [
      ("send-preview", "离线发送验收", "paperplane"),
      ("send-queue", "Queue 验收", "list.bullet"),
      ("session-share-preview", "Conversation sharing", "link"),
      ("send-guide", "引导发送验收", "arrow.uturn.forward"),
      ("send-scroll-guide", "长上下文 · 直接插话", "arrow.uturn.forward"),
      ("send-scroll-queue", "长上下文 · 队列插话", "list.bullet"),
      ("send-scroll-normal", "长上下文 · 普通发送", "paperplane"),
      ("send-interrupt", "Queue 中断验收", "stop.circle"),
    ]),
  ]

  private let list = LodyGroupedList(frame: .zero)
  private var observer: NSObjectProtocol?

  init() { super.init(nibName: nil, bundle: nil); title = "Debug" }
  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    SettingsPage.host(list, in: self) { [weak self] name, body in
      guard name == "rowPress", let id = body["id"] as? String else { return }
      self?.press(id)
    }
    list.setPlaceholder("")
    observer = NotificationCenter.default.addObserver(forName: .lodyDataRuntimeEvent, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.render() }
    }
    render()
  }

  private func render() {
    var sections = Self.groups.map { group in
      LodyListSection.group(group.id, header: group.header, group.rows.compactMap { id, title, image -> LodyListRow? in
        #if !DEBUG
        if id == "push-subscription-verify" { return nil }
        #endif
        return LodyListRow.item(id, title, image: image, disclosure: id != "push-subscription-verify")
      })
    }
    var hang = LodyListRow.item("runtime-hang", "卡死 WebView JS", image: "exclamationmark.triangle")
    hang.destructive = true
    sections.append(.group("runtime", header: "数据运行时",
      footer: "故障注入会暂时中断同步。看门狗应自动重建；连续故障达到上限后，请返回项目页下拉重新同步。", [
        runtimeRow(),
        hang,
        .item("runtime-restart", "模拟 WebContent 进程丢失", image: "arrow.clockwise"),
      ]))
    list.setSections(sections)
  }

  private func runtimeRow() -> LodyListRow {
    guard let status = DataRuntime.current?.status() else {
      return .item("runtime-state", "无法读取运行时状态", image: "cpu", action: false)
    }
    let generation = (status["generation"] as? Int).map { "#\($0)" }
    let details = [generation, status["reason"] as? String, status["lastStartReason"] as? String]
      .compactMap { $0 }.filter { !$0.isEmpty }
    return .item("runtime-state", status["state"] as? String ?? "unknown", subtitle: details.joined(separator: " · "),
      image: "cpu", action: false, subtitleMono: true)
  }

  private func press(_ id: String) {
    switch id {
    case "runtime-hang": DataRuntime.current?.debugHang()
    case "runtime-restart": DataRuntime.current?.debugRestart()
    #if DEBUG
    case "push-subscription-verify":
      PushNotifications.shared.onRegistered = { [weak self] in
        guard let self else { return }
        PushNotifications.shared.verify(from: self)
      }
      PushNotifications.shared.verify(from: self)
    #endif
    default: DebugSceneCoordinator.open(["verifyCase": id])
    }
  }
}
