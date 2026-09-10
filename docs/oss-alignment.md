# OSS 功能对齐跟进

日期：2026-09-11

对照官方开源仓 [LodyAI/Lody](https://github.com/LodyAI/Lody)（本机常见路径 `/Users/innei/git/fork/Lody`，当时 `main` @ `4400744a`）。OSS 开源的是 **桌面 Electron + CLI**；官方手机端不在该仓。iOS 要对齐的是同一套 session 文档、发送协议和会话工具语义，再按 Apple HIG 做移动端呈现，不是把桌面 IDE 搬过来。

状态：`done` 已对齐 · `wip` 工作区已开工、未齐 · `missing` 移动端也该有、尚未做 · `drift` 做了但语义偏移 · `wont` 桌面 / CLI 专属，不跟。

勾完一项时改状态，并在文末「修订」补一行。刷新对照时先更新下方基线再改条目。

## 基线

| 侧 | 位置 | 当时版本 |
|----|------|----------|
| 官方 OSS | `apps/electron` + `packages/components` + `packages/shared` + `apps/cli` | `4400744a` |
| 本仓 | `apps/mobile` + `modules/lody-kit` | 2026-09-11 工作区（含未提交 mentions / project-history / model panel） |

协议真相源：

- Session 文档：OSS `packages/shared/src/schema.ts`（`session` / `history` / `mq` / `forkOperation` / `preview` / `externalHistoryCursor` / `acpRuntimeConfig`）
- 发送与控制：`session/chat`、`session/steer`、`session/cancel`、`session/permission_request`、`session/permission_response`
- Run config：`packages/shared/src/acp-run-config.ts`
- Mentions：`packages/components/src/components/mentions/`（`file` / `skill` / `session` / `role` / `issue` / `pr` / `cmd`）

---

## GitHub 跟进

跟踪父 issue：[#7 OSS 功能对齐](https://github.com/Innei/lody-ios/issues/7)。写法按 lobe-chat Linear skill：标题带顺序前缀、按域嵌套、正文自洽、Blocked by / Relates 互链，并 related 上游 `LodyAI/Lody`。

```
#7
├─ #8   [1]     [protocol]  时长减去 permissionWaitMs
├─ #9   [2]     [question]  Ask-user question 专用卡
├─ #10  [3]     [role]      Agent Role
│   ├─ #18  [3.1]  继承 Role 并允许续聊
│   └─ #19  [3.2]  选择与创建 Role
├─ #11  [4]     [mention]   Mentions 对齐
│   ├─ #20  [4.1]  发送时 expansion
│   ├─ #21  [4.2]  @session
│   ├─ #22  [4.3]  @role
│   ├─ #23  [4.4]  @issue / @pr
│   └─ #24  [4.5]  slash command
├─ #12  [5]     [mcp]       本机回合使用 MCP
├─ #13  [6]     [session]   会话工具
│   ├─ #25  [6.1]  Fork
│   ├─ #26  [6.2]  重命名
│   ├─ #27  [6.3]  编辑并重发
│   ├─ #28  [6.4]  队列编辑与重排
│   └─ #29  [6.5]  搜索 / 钉历史 / 未读 / 偏好
├─ #14  [7]     [create]    新建会话 worktree 与 Role
├─ #15  [8]     [workspace] PR / CI 只读
├─ #16  [9]     [workspace] Usage 只读
└─ #17  [10]    [transcript] 对话块补齐
```

## 建议顺序

按「用户能感知、改动面可控」排。单项开工前另写 design，不要直接把本表当实施计划。

1. #8 时长减去 `permissionWaitMs`（小、字段已投、OSS 刚修）
2. #9 Ask-user question 专用卡（Live Activity 已报 `question`）
3. #18 Agent Role：至少能继承并继续发，再 #19 选择 / #22 @
4. Mentions：#20 expansion，再补 #21 `session` + #22 `role`
5. #12 MCP 按回合带上（设置文案现等于承认缺）
6. #25 Fork / #26 重命名 / #27 编辑重发 / #28 队列编辑
7. #15 PR 只读 + #16 usage 只读

---

## 已对齐

| 状态 | 项 | 本仓锚点 | OSS 锚点 / 证据 |
|------|----|----------|-----------------|
| done | 读会话、发文字回合、附件、失败草稿恢复 | `data-runtime/session.ts`、`useSessionSend.ts`、`SessionAttachments.swift` | `session/chat`；丢失 ACK 不自动重放 |
| done | 忙时 FIFO `mq` 队列 | `session.ts`（`getMovableList('mq')`） | OSS 可移动队列；`session-runtime.test.mjs` |
| done | Stop / Steer | `useSessionControl.ts`、`session.ts` `controlTurn` | `session/cancel`、`session/steer`；`session-control.test.mjs` |
| done | 权限请求读写回 | `PermissionScreen.tsx`、`permission-oss.test.mjs` | OSS `896fd1e` sessionDocSchema 快照；桌面先答则 sheet 自关 |
| done | 归档语义 | `archive-session.ts` | session flag 即归档；机器清理尽力 |
| done | 列表 pin / archive / mark read | `sessionActions.ts`、`SessionScreen.tsx` | `isPinned` / `isArchived` / `lastReadAt` |
| done | 搜索（含归档） | `InboxScreen.tsx` | OSS home / archive 过滤 |
| done | 文件树、回合变更、全文 diff | `FilesScreen.tsx`、`TurnChangesScreen.tsx`、`FileDiffScreen.tsx` | 移动端预期能力（README） |
| done | Worked-for 紧凑格式 | `ChatWorkDuration`、`verification/chat/main.swift` | `1h 01m 05s`；**减法见偏移** |
| done | 推送 + Dynamic Island | `PushNotifications.swift`、`live-activity/` | 官方 README 的 mobile 职责；岛内批准见缺失 |
| done | 模型 / effort / mode / permission | `ModelScreen.tsx`、`ChatComposerModelPanel.swift` | 同一 ACP capability；UI 不同 |
| wip | @ mentions（仅 file + skill） | `mentions.ts`、`ChatMentionPanel.swift`、`MentionPickerScreen.tsx` | 七类里只接了两类，见缺失 |
| wip | Agent Conversation Sync UI | `ProjectHistoryScreen.tsx`、`project-history.ts` | 导入在机器侧；手动批量，非自动镜像 |
| wip | Composer 原生 model panel | `ChatComposerModelPanel.swift` | 语义对齐 ModelScreen，玻璃面是 iOS 形态 |

---

## 缺失

移动端合理、OSS 已有、本仓没有或只露了半截。

### Mentions 与跨会话

| 状态 | 项 | 缺口 | 本仓锚点 | OSS 锚点 |
|------|----|------|----------|----------|
| wip | `@file` / `$skill` | 工作区已接目录与 skill 扫描；大项目截断（文件上限 2 万）；发送无 expansion | `data-runtime/mentions.ts`、`src/models/mentions.ts` | `mentions/mention-registry.ts`、`mention-expansion.ts` |
| missing | `@session` | 不能引用其他会话；跨会话协调入口缺失 | `MentionCategory = 'file' \| 'skill'` | namespace `session` |
| missing | `@role` | 不能 @ Agent Role | 同上 | namespace `role`；`packages/shared/src/agent-role.ts` |
| missing | `@issue` / `@pr` | 不能 @ GitHub Issue / PR | 无 | namespace `issue` / `pr` |
| missing | `/` command | 无 slash command 目录 | 无 | namespace `cmd` |
| missing | 发送时 expansion | 现为往输入框塞文本；skill 插入 `use /token [Skill Path](<path>)` 提示语 | `mentions.ts` `insertText` | `mention-expansion.ts`（role 前缀、session 引用、skill 改写） |

### Agent Roles

| 状态 | 项 | 缺口 | 本仓锚点 | OSS 锚点 |
|------|----|------|----------|----------|
| missing | 选择 / 创建 Role | composer 与设置都没有 Role | `ModelScreen.tsx` 只有 model / mode / effort / extras | `composer-agent-role-panel.tsx`、`agent-roles-setting.tsx` |
| drift | 带 Role 的会话续聊 | 上一回合有 `agentRoleId` 时发送抛 `agent_role_requires_configuration`，桌面开过 Role 的会话手机发不出去 | `data-runtime/session.ts` ~422 | 应继承 `agentRoleId` / revision，而不是拒发 |

### MCP

| 状态 | 项 | 缺口 | 本仓锚点 | OSS 锚点 |
|------|----|------|----------|----------|
| drift | 设置只改别人 | 可编辑 MCP 默认，文案写明同步给其他客户端新会话 | `settings.remote.mcpHint`、`RemoteSettingEditorScreen.tsx` | `mcp-setting.tsx`、`workspace-mcp.ts` |
| missing | 本机回合使用 MCP | 发送只继承 `previous.mcpServerIds`，composer 不能按回合开关 | `session.ts` `inputConfig.mcpServerIds` | composer attachment 菜单按回合 toggle |

### Ask-user questions

| 状态 | 项 | 缺口 | 本仓锚点 | OSS 锚点 |
|------|----|------|----------|----------|
| missing | 多题 elicitation | 无专用答题卡、无倒计时自动继续；多半落到通用权限 sheet 或当普通事件 | `PermissionScreen.tsx` 只覆盖 execute / edit / tool；`project.ts` 无 ask-user 投影 | `ask-user-question.ts`；`PermissionRequestKind` 含 `ask_user_question`；`ask-user-question-card.tsx` |
| drift | Live Activity 已认识 question | 岛上能提示「有问题」，点进会话对不上 OSS 问答 | `LodyActivityAttributes` `statusCounts.question` | 官方 mobile 从岛上处理 question / permission |

### 会话工具

| 状态 | 项 | 缺口 | 本仓锚点 | OSS 锚点 |
|------|----|------|----------|----------|
| missing | Fork | 不能分叉到共享 tab 或新 worktree | `SessionScreen` 菜单无 fork | `session-fork-destination-menu.tsx`、`forkOperation` |
| missing | 重命名 | 标题只读 | 无 | `rename-session-dialog.tsx`；MCP `lody_session_rename` |
| missing | 永久删除 | 只有归档 | `archive-session.ts` | `session-delete-queue.ts` |
| missing | 编辑并重发 | 不能改上一句用户回合 | 无 | locales `sessions.editMessage` / `saveAndResend` |
| missing | 队列编辑 / 重排 | 只能入队、Steer、Stop | `ChatQueueView` | `message-queue/`（`isEditing` + lease） |
| missing | 会话内搜索 | 无 transcript find | 无 | `session-search-context.tsx` |
| missing | 钉一条历史 | 只有列表 pin | `setPinned` | `session-pin.tsx` |
| missing | 标记未读 | 只能标已读 | `archive-session.ts` `lastReadAt` | `sessions.contextMenu.markUnread` |
| missing | 自动归档 | 无设置 | 无 | `auto-archive-setting.tsx` |
| missing | 忙时 queue vs steer-guide | 无偏好，行为写死 | `session.ts` queued 判定 | `queued-message-behavior-control.tsx`、`session-message-submit-route.ts` |

### 新建会话

| 状态 | 项 | 缺口 | 本仓锚点 | OSS 锚点 |
|------|----|------|----------|----------|
| missing | Worktree 模式 | 新会话不能选隔离 worktree | `CreateSessionScreen.tsx`、`create-session.ts` | `chat-landing.tsx`、`worktree-paths.ts` |
| missing | 创建时选 Role | 只有机器 / agent / 模型 / GitHub 分支 | 同上 | `mobile-new-chat-sheet.tsx` |

### PR / 评论 / Usage

| 状态 | 项 | 缺口 | 本仓锚点 | OSS 锚点 |
|------|----|------|----------|----------|
| missing | PR / CI 只读 | 能看文件和 diff，无 PR 状态、checks、merge | 无 PR screen | `pr-tab-view.tsx`、`pull-request-badge.tsx` |
| missing | 行级评论 | 不能读 / 写 diff 或 GitHub review 线程 | 无 | `session-comment-types.ts`、`comment-reference-chip.tsx` |
| missing | Usage | 无 context / token / quota 入口 | 无 | `session-usage-popover.tsx`、`usage-calendar-visualization.tsx` |

### 对话块与身份

| 状态 | 项 | 缺口 | 本仓锚点 | OSS 锚点 |
|------|----|------|----------|----------|
| done | thought / plan / subagent_task / tool_call 投影 | 能投、能摘要 | `ChatTranscript.swift`、`project.ts` | `packages/shared/src/ai.ts` |
| missing | Goal 横幅 / `/goal` | 无 ACP goal 生命周期 | 无 | `goal.ts`、`session-goal-banner.tsx` |
| missing | 定时任务 | 不展示 cron / wakeup | 无 | `scheduled-tasks-panel.tsx` |
| missing | Agent 产出文件卡片 | 无预览 / 下载入口 | 附件主要是用户发出 | `session-file-card.tsx` |
| missing | 发送者身份 | 团队会话不显示谁发的 | 无 | `#524` `show chat sender identities` |
| missing | 大段粘贴 chip | 长粘贴整段进输入框 | `ChatComposerView` paste | `pasted-text-draft.ts` |
| drift | `system_notice` | `agent_warning` 被丢掉，不展示 | `ChatTranscript.swift` 过滤 `system_notice` + `agent_warning` | 应可见的系统通知 |

### 官方 mobile 有、本仓没有

| 状态 | 项 | 缺口 | 本仓锚点 | 说明 |
|------|----|------|----------|------|
| missing | 岛内批准权限 | 设计明确不做岛内同意 / 拒绝 | `docs/superpowers/specs/2026-09-09-live-activity-design.md` Non-goals | 官方 README 展示从灵动岛批准 |
| drift | 杀进程后的桌面新会话 | 可能要等重新打开才上岛 | 同上 | 未用 push-to-start 时杀进程丢桌面新开会话 |
| drift | Device Flow 客户端名 | 授权页显示 `lody-cli` | `login.footnote`、AGENTS.md | 服务端未注册独立 iOS client 前保持透明 |

---

## 偏移

做了，但和 OSS 不是同一套语义。修的时候优先对协议，不要只改文案。

| 状态 | 项 | 本仓现在 | OSS | 锚点 |
|------|----|----------|-----|------|
| drift | 时长含权限等待 | Swift 用 `end - start`，**不减** `permissionWaitMs` | `resolveSessionHistoryDurationMs`：`endedAt - timestamp - permissionWaitMs`（`4d6eaca3`） | 字段已在 `project.ts` / `src/models/session.ts`；`ChatEntry` / `ChatWorkDuration.milliseconds` 未用 |
| drift | Mentions 插入形态 | 本地 `insertText`；skill 是提示语 | 发送时 expansion | `mentions.ts` vs `mention-expansion.ts` |
| drift | MCP / Role 继承 | 抄上一回合 MCP / `taskToolsEnabled`；有 Role 则拒发 | 可改 MCP；Role 可继承或重选 | `session.ts` `inputConfig` |
| drift | 项目历史 | 手动批量导入 + 冲突确认 | 导入 UI 在桌面 / 本机；手机读已导入会话 | README「不是自动镜像」；`settings.history.hint` |
| drift | 权限 UI | 单请求、单列选项 | 多题卡 + 自动继续 | `PermissionScreen.tsx` |
| drift | 目录 / 文件上限 | 副本 8 MiB；目录前 2000 条 | 桌面无此移动端天花板 | AGENTS.md；`files.ts` `listDir` |
| drift | Auth 客户端身份 | `lody-cli` Device Flow | 官方 App 有独立客户端 | 等服务端注册再改声称 |

---

## 不做

桌面 / CLI / 本机执行专属。用户问「为什么没有」时指向这里，不要当欠债开 issue。

| 状态 | 项 | 原因 |
|------|----|------|
| wont | 内置终端、命令面板、快捷键 | Electron / PTY |
| wont | Monaco 编辑、用外部 IDE 打开 | 本机 path launcher |
| wont | 任意 URL 浏览器 | OSS 已标 `desktopOnly` |
| wont | 会话内 Preview + 可视化标注 | 需要内嵌浏览器 |
| wont | 在手机「添加本地项目」 | 目录在机器上；手机只浏览 / 注册远端机器上的目录 |
| wont | 多 Tab / 侧栏 / outline rail | 宽屏 IDE 布局 |
| wont | 聊天导出 PNG | 桌面 IPC / 保存面板 |
| wont | 本机执行 worktree 文件系统操作 | 机器 / CLI |
| wont | ACP 历史导入的执行端 | `canImport: isElectron`；手机只读已导入 |
| wont | OSS local 平台关掉的云能力 | 团队计费、GitHub App broker、远程预览隧道（走官方云产品，不走 OSS local） |

iOS 自己的边界（不是 OSS 差距）：无 Android、不自动重放写入、发送不用 `BGContinuedProcessingTask`、不复用桌面凭据、Metro 不进 `@lody/shared` 根入口。

---

## 本仓相关文件

开工前先读这些，避免再扫一遍仓。

| 域 | 文件 |
|----|------|
| 发送 / 队列 / Role 拒发 | `apps/mobile/modules/lody-kit/data-runtime/session.ts` |
| 归档 / pin / read | `apps/mobile/modules/lody-kit/data-runtime/archive-session.ts` |
| Mentions RPC | `apps/mobile/modules/lody-kit/data-runtime/mentions.ts` |
| Mentions 类型 | `apps/mobile/src/models/mentions.ts` |
| Mentions UI | `ChatMentionPanel.swift`、`LodyMentionPickerView.swift`、`useComposerMentions.ts`、`MentionPickerScreen.tsx` |
| 时长 | `apps/mobile/modules/lody-kit/ios/Chat/ChatTranscript.swift`（`ChatWorkDuration`） |
| 权限 | `apps/mobile/src/screens/PermissionScreen.tsx` |
| 模型 | `apps/mobile/src/screens/ModelScreen.tsx`、`ChatComposerModelPanel.swift` |
| 新建 | `apps/mobile/src/screens/CreateSessionScreen.tsx`、`data-runtime/create-session.ts` |
| 投影类型 | `apps/mobile/modules/lody-kit/data-runtime/project.ts`、`apps/mobile/src/models/session.ts` |
| MCP 文案 | `apps/mobile/locales/en.json` `settings.remote.mcpHint` |
| 项目历史 | `ProjectHistoryScreen.tsx`、`data-runtime/project-history.ts` |
| OSS 协议测 | `tests/native/permission-oss.test.mjs`、`session-runtime.test.mjs`、`session-control.test.mjs` |
| Live Activity 非目标 | `docs/superpowers/specs/2026-09-09-live-activity-design.md` |

---

## 怎么刷新对照

1. 更新本机 OSS：`cd /Users/innei/git/fork/Lody && git pull && git log -1 --oneline`
2. 把新的 SHA 写进「基线」
3. 扫 OSS：`packages/shared/src/schema.ts`、`packages/shared/src/ai.ts`、`packages/components/src/components/mentions/`、`packages/components/src/components/sessions/`、README「More built in」
4. 只改状态与新增行，不要重写已勾条目的历史；修订记在下面

---

## 修订

| 日期 | 说明 |
|------|------|
| 2026-09-11 | 初稿。对照 OSS `4400744a` 与当时 iOS 工作区。 |
| 2026-09-11 | 拆成 GitHub #7–#29。写法跟 lobe-chat Linear skill；父子嵌套 + Blocked by / Relates + 上游链接。 |
