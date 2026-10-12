# OSS 功能对齐跟进

日期：2026-10-12

对照官方开源仓 [LodyAI/Lody](https://github.com/LodyAI/Lody/tree/987962e77022df6a800f4e889f124b51f6eb8056) 的桌面 Electron、CLI、共享文档与公开 Cloud 接口，固定版本为 `987962e77022df6a800f4e889f124b51f6eb8056`。iOS 使用同一套会话、发送、目录与机器执行语义，界面遵循 Apple HIG。官方手机 App 的源码不在该仓；OSS 中的 mobile 组件可用于核对产品行为。

本页登记当前工作区的实现与范围。`implemented` 表示代码已接入所选方案，`existing` 表示本轮前已有实现、继续保留，`tracking` 表示父级汇总项。它们均不表示已经发布、GitHub issue 已关闭或生产验收通过。`wip` 表示实现或接线仍在收口，`pending` 表示尚待验证，`outside` 表示本次新增功能范围之外，`wont` 表示明确的产品边界。

本轮 470 项 Node 行为测试、61 项 UI runner 行为检查、生产 UIKit composer 检查、`bundle` 和正常签名 Release Simulator build 已通过。`check` 的类型、i18n、原生源与许可证检查通过，剩余为任务开始前已有的 macOS `TOKENS.md` 格式告警。最终候选的英文 light/dark 20 个手机场景共 40 项检查已通过并完成独立截图/录像审阅；原始 34 项通过、6 项失败与随后 6 次完整浅色重跑分别保留。真实 Share Extension 两主题、iPad 两主题补充检查及 CreateSession 修改前后 20 组画面对照也已通过并完成独立审阅。真实 Cloud、机器执行、TestFlight 和物理设备行为仍需分别验证。

## 基线

| 侧                 | 位置                                                                                        | 固定版本 / 状态                                                                                                            |
| ------------------ | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| 官方 OSS           | `apps/electron`、`apps/cli`、`packages/components`、`packages/shared`、`packages/cloud-api` | [`987962e77022df6a800f4e889f124b51f6eb8056`](https://github.com/LodyAI/Lody/tree/987962e77022df6a800f4e889f124b51f6eb8056) |
| 本仓协议           | `packages/cloud-runtime/src/models`、`protocol`、`runtime`                                  | 2026-10-12 工作区实现候选                                                                                                  |
| 本仓 iOS           | `apps/mobile/src`、`apps/mobile/modules/lody-kit`、`packages/lody-core`                     | 原生组件与单一 LodyKit 桥；英文双主题手机 UI 已验证，生产验证 pending                                                      |
| 历史 Mentions 专项 | `packages/components/src/components/mentions`                                               | 2026-09-11 对照 `63ae7ad5`；本轮统一参考上述固定版本                                                                       |

旧文档中的 `apps/mobile/modules/lody-kit/data-runtime/*.ts` 路径已经过时；协议源码现位于 `packages/cloud-runtime/src/runtime/*.ts`，原生仍拥有 WebView 生命周期、凭据、订阅与命令入口。

协议真相源：

- Session / history / queue / fork：OSS `packages/shared/src/schema.ts`、`ai.ts`、`acp-run-config.ts`、`apps/cli/src/session/`。
- MCP / Role / Provider：`workspace-mcp.ts`、`agent-role.ts`、`machine-flock.ts`、`message.ts`；Agent 目录同时兼容 alive legacy metadata 与 Machine Flock。
- Schedule：`schedule-types.ts`、`schedule-schema.ts`、`schedule-registry.ts` 及机器侧 ScheduleRepository。
- Prompt Shortcuts：`packages/shared/src/prompt-shortcuts/` 和公开 Cloud 操作；独立授权的 index / body 文档。
- Cloud 管理：`packages/cloud-api/src/index.ts`；授权、凭据和固定操作名在原生边界检查。

## 开放 issue 映射

以下覆盖本轮读取的 **31 个开放 issues**：19 项本轮实现、6 项已有功能回归、3 项父级追踪、3 项范围外事项。父 issue 的完成依赖子项验收；已有功能保留原实现，不因 issue 仍开放而重复开发。确定性离线 UI 已按 12 项业务结果、26 个明暗主题槽位收集证据；这不代替真实服务验证或用户验收，具体边界见后文。

| Issue                                                                          | 状态        | 当前实现 / 本轮范围                                                                                                              |
| ------------------------------------------------------------------------------ | ----------- | -------------------------------------------------------------------------------------------------------------------------------- |
| [#7 OSS 功能对齐](https://github.com/Innei/lody-ios/issues/7)                  | tracking    | 本表汇总协议、会话、管理能力；子项验收后再收口父 issue。                                                                         |
| [#10 Agent Role](https://github.com/Innei/lody-ios/issues/10)                  | tracking    | 保留 Role 续聊继承；#19 增加已有 Role 的选择与清除，#14 消费同一目录。                                                           |
| [#12 本机回合 MCP](https://github.com/Innei/lody-ios/issues/12)                | implemented | 聊天、新建与共享表单选择 MCP；未指定继承，明确空集合关闭；首条/普通/队列共用冻结选择。                                           |
| [#13 会话工具](https://github.com/Innei/lody-ios/issues/13)                    | tracking    | 聚合 #25–#29、#44；保留现有 pin、archive、read 与删除入口。                                                                      |
| [#14 新建 worktree 与 Role](https://github.com/Innei/lody-ios/issues/14)       | implemented | 本地项目按机器 Git 能力选择当前目录/新 worktree；Role、MCP 与项目偏好贯穿首回合。                                                |
| [#15 PR / CI 只读](https://github.com/Innei/lody-ios/issues/15)                | existing    | 保留会话 PR 关联、状态、checks 与系统链接；本轮纳入回归。                                                                        |
| [#16 Usage 只读](https://github.com/Innei/lody-ios/issues/16)                  | implemented | 复用 token detail，增加完成态 token、当前 context 与精确配置/model quota；无上报不显示伪造的 0。                                 |
| [#17 对话块补齐](https://github.com/Innei/lody-ios/issues/17)                  | implemented | Goal、只读定时摘要、relay 文件状态、发送者/Agent 来源、可见系统通知；保留已有 rich-paste 文件 chip。                             |
| [#19 选择与创建 Role](https://github.com/Innei/lody-ios/issues/19)             | implemented | 按 issue 正文允许的“只读选择 + 桌面创建”方案交付：目录/详情、选择/清除、revision 与绑定校验；Role 创建编辑留在桌面。             |
| [#25 Fork](https://github.com/Innei/lody-ios/issues/25)                        | implemented | 会话菜单/回合入口，按具体配置能力提供共享目录或新 worktree；准备、完成和未知结果有独立状态。                                     |
| [#26 重命名](https://github.com/Innei/lody-ios/issues/26)                      | existing    | 保留原生重命名与 metadata 写入；本轮纳入回归。                                                                                   |
| [#27 编辑并重发](https://github.com/Innei/lody-ios/issues/27)                  | existing    | 保留 history rewind、附件/草稿恢复与明确重发；队列编辑仍走 #28 的独立协议。                                                      |
| [#28 队列编辑与重排](https://github.com/Innei/lody-ios/issues/28)              | implemented | 稳定 userTurnId、五分钟 lease、编辑/保存/取消、上移/下移；保留附件与 run config。                                                |
| [#29 搜索 / 钉历史 / 未读 / 偏好](https://github.com/Innei/lody-ios/issues/29) | implemented | 保留搜索/忙时 queue-guide；增加内容置顶、未读、PR 合并后的自动归档偏好，默认关闭。                                               |
| [#44 搜索正文](https://github.com/Innei/lody-ios/issues/44)                    | existing    | 保留原生 find、搜索跳转与 prose 索引；补元数据 branch/rootPath fallback，纳入回归。                                              |
| [#45 Inbox 置顶分组](https://github.com/Innei/lody-ios/issues/45)              | existing    | 保留 iPhone/iPad 共用分组和工作区本机固定顺序；跨端手动顺序仍取决于上游协议。                                                    |
| [#53 发送确认卡死](https://github.com/Innei/lody-ios/issues/53)                | implemented | 有界确认、只读检查和显式继续编辑；解除本地锁不重放写入、不宣称停止机器执行。                                                     |
| [#54 Preview 关闭入口](https://github.com/Innei/lody-ios/issues/54)            | implemented | 可见 ×；共享中请求撤销 tunnel，候选 URL 仅隐藏；失败保留重试和草稿。                                                             |
| [#63 删除队列消息](https://github.com/Innei/lody-ios/issues/63)                | implemented | 指定项删除与本机准备/上传取消；机器取出竞争、lease 和未知 append 保留准确的待确认状态。                                          |
| [#64 子任务完整记录](https://github.com/Innei/lody-ios/issues/64)              | implemented | 按父会话/回合/task/run 绑定 retained execution items，复用只读 NativeChat，分页、实时刷新、退出释放。                            |
| [#65 proposed_plan](https://github.com/Innei/lody-ios/issues/65)               | existing    | 保留完整 Markdown、增量/完成/清除、历史/最新、复制/搜索与权限关联；本轮纳入回归。                                                |
| [#66 定时任务管理](https://github.com/Innei/lody-ios/issues/66)                | implemented | 上游 registry/body、规则/时区、目的地、CRUD/控制、proposal 和历史入口已接入。                                                    |
| [#67 项目管理](https://github.com/Innei/lody-ios/issues/67)                    | implemented | 远程配置脚本、共享范围、移除预检查/待处理/结果、可选 worktree 清理和 Skills；保留目录添加/历史导入。                             |
| [#68 ACP Provider 管理](https://github.com/Innei/lody-ios/issues/68)           | implemented | 当前机器 Flock 配置 CRUD、验证/模型、认证、运行时安装更新/任务、标题配置；操作受能力与所有者权限控制。                           |
| [#69 Prompt Shortcut](https://github.com/Innei/lody-ios/issues/69)             | implemented | 工作区 CRUD、作用域/可见性、结构化稳定引用、@ 与 slash 发现、首条/普通/队列一致展开。                                            |
| [#70 团队管理](https://github.com/Innei/lody-ios/issues/70)                    | implemented | 成员搜索/分页、邀请/接受、加入申请、角色/移除、退出/所有权转移；席位信息只展示服务端提供的数据。                                 |
| [#71 Bug 反馈入口](https://github.com/Innei/lody-ios/issues/71)                | implemented | Settings → 反馈、环境信息、可选脱敏诊断/截图、编辑/预览、复制/分享、预填本仓 GitHub issue。                                      |
| [#74 Claude Assistant 缺失](https://github.com/Innei/lody-ios/issues/74)       | implemented | 合并 alive legacy Agent 元数据与机器 Flock，同 ID 后者优先；过滤原因以计数诊断。已复现并修复兼容缺口，报告者生产副本原因未确认。 |
| [#4 Expo Modules API 2.0 迁移](https://github.com/Innei/lody-ios/issues/4)     | outside     | 上游运行时与 mixed-mode 桥接迁移追踪；本轮未作为新功能展开，也未宣称已迁完。                                                     |
| [#6 TestFlight 启动崩溃](https://github.com/Innei/lody-ios/issues/6)           | outside     | 历史 iPhone 17 / Hermes 启动崩溃调查；需要新 TestFlight 和真机重复冷启动，Simulator 验证不能关闭此故障。                         |
| [#49 Video Promo](https://github.com/Innei/lody-ios/issues/49)                 | outside     | issue 内容为宣传视频引用；本轮未制作、替换或发布宣传素材。                                                                       |

## 保留的已实现能力

下列能力在本轮前已有实现。原文中的 missing/drift 已不准确；这里登记当前源码，统一回归结果另记。

| 域                    | 已实现行为                                                                          | 本仓锚点                                                                                                                                                    |
| --------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 基本会话              | 文字/附件发送、失败草稿恢复、FIFO mq、Stop/Steer、权限回答                          | `packages/cloud-runtime/src/runtime/session.ts`、`apps/mobile/src/features/sessions/useSessionSend.ts`、`useSessionControl.ts`                              |
| 时长 #8               | Worked-for 减去 permissionWaitMs，非法等待时长按 0，live/完成态共用公式             | `apps/mobile/modules/lody-kit/ios/Chat/ChatTranscript.swift`                                                                                                |
| Ask-user #9           | 专用问题卡、顺序回答/自动继续与现有权限入口                                         | `apps/mobile/src/features/sessions/QuestionCard.tsx`、`apps/mobile/src/cloud/permissionQuestions.ts`、`PermissionScreen.tsx`                                |
| Role 续聊 #18         | 继承历史冻结 run config 与 Role provenance；不重新解析目录或重放前缀                | `packages/cloud-runtime/src/runtime/session.ts`                                                                                                             |
| Mentions #11、#20–#24 | file/skill/session/role/issue/pr/cmd 的发现、稳定引用与持久化前展开                 | `packages/cloud-runtime/src/runtime/mentions.ts`、`mention-expansion.ts`；[Mentions 设计](mentions-design.md)                                               |
| 会话列表与搜索        | archive、pin、read、rename、delete；原生正文 find，置顶分组/本机顺序                | `packages/cloud-runtime/src/runtime/archive-session.ts`、`apps/mobile/src/features/sessions/sessionActions.ts`、`inbox.ts`、`ChatFindBar.swift`             |
| 历史编辑与计划        | 编辑重发、history rewind、proposed_plan 正文与批准流程                              | `packages/cloud-runtime/src/runtime/edit-session.ts`、`apps/mobile/src/features/sessions/useEditableMessage.ts`、`useProposedPlan.ts`、`ChatPlanCell.swift` |
| 查看变更与 PR         | 文件树、回合变更、全文 diff、PR 状态与 CI checks                                    | `apps/mobile/src/screens/FilesScreen.tsx`、`TurnChangesScreen.tsx`、`FileDiffScreen.tsx`、`PullRequestScreen.tsx`                                           |
| 原生输入              | model/effort/mode/permission；rich paste、长文本转 Text.md/Text.txt chip 与撤销恢复 | `apps/mobile/modules/lody-kit/ios/Chat/ChatComposerView.swift`、`ChatComposerModelPanel.swift`、`ChatAttachments.swift`                                     |
| 历史导入              | Agent Conversation Sync 手动批量导入与冲突确认，执行在远程机器                      | `apps/mobile/src/screens/ProjectHistoryScreen.tsx`、`packages/cloud-runtime/src/runtime/project-history.ts`                                                 |
| 通知与分享            | 原生 Push、Live Activity、Share Extension 离线表单/收件箱                           | `apps/mobile/modules/lody-kit/ios/Notifications/`、`apps/mobile/src/features/share/`                                                                        |

## 实现方案与边界

### Run options 与 Assistant 兼容

Role 使用既有 workspace catalog。新选择校验可见性、机器/Provider 精确绑定和 revision；修改固定配置明确解除 Role provenance，清除 Role 保留当前 run 值。Role 前缀只进入新会话首条回合。MCP 的未指定、继承和明确空集合保持不同语义；已冻结回合不随设置默认值变化。

本地 worktree 先读官方 `local-project/git-state`，仅 Git 项目且有分支时提供选择；GitHub 项目仍要求 base branch。机器执行 Git，Chat 无 worktree 控件。Share Extension 继续只消费无凭据快照，并在 App 中复核过期选择。

Assistant 目录兼容 OSS 两代存储：alive `m/agent-<id>` metadata（含字段覆盖）与机器 `agentConfig`，按 id 合并后再限制本地项目机器。旧版仅有 legacy 的合法配置能创建会话。未迁移的 legacy 配置管理仍由桌面完成；Provider 管理操作当前 Machine Flock 定义。开发诊断只记录来源计数和拒绝原因，不输出 env、prompt、启动配置或凭据。#74 的确定性兼容复现已修复，报告者账号尚未读生产副本。

方案见 [MCP / Role / Worktree](oss-run-options-design.md)。

### 发送、队列与会话工具

确认恢复读取新的有界服务器文档，以同一 userTurnId 的 queue/history 为依据。手动解除本地确认锁前有明确说明；它不会再次写 history、dispatch pointer 或 Machine RPC。准备/上传取消只在发送交给 runtime 前生效，并只清理该发送拥有的资源。

队列编辑使用 OSS 五分钟 lease 和取得时的 timestamp，保存仍是同一项并保留附件/run config；重排写 movable list。上游没有原子 remove-if-unclaimed 操作，删除后队列项消失仍不能证明机器没有取走，因此保留“执行待确认”回执，允许检查或解除本地回执。已开始的消息显示 started，删除不调用 Stop。

Fork 使用 `session/fork` 和具体 Agent 的 Fork/ForkWorktree 能力；dirty 目标要求明确确认，preparing 与完成由权威文档判断。未知写入只检查结果。内容 pin 使用 pinnedHistoryId，与列表 isPinned 分开；未读保留持久化 lastReadAt 与本地 viewed 状态。自动归档默认关闭、按账号隔离，只处理本人会话同一 PR 的合并状态转换。#45 的置顶顺序仍是每工作区本机存储；上游跨设备顺序字段未就绪。

方案见 [发送与队列](oss-send-queue-design.md)、[会话工具](oss-session-tools-design.md)。

### Usage、对话块与子任务

Token、context、quota 按实际报告投影；quota 按精确 Provider 配置/model 匹配，缺字段保持缺失。Goal 优先读历史、catalog 作回退，清除后消失；Cron/Wakeup 摘要按记录的规则、时区和删除/触发事件重建。relay 文件明确 pending、大小和过期，复用原生预览/分享。团队人类回合显示冻结作者身份；solo 会话保留 Agent 来源。系统通知与 warning 可见，独立于过程摘要。

子任务记录仅使用协议保留的内容，绑定父会话、父回合、task 与具体 run，分页和订阅不跨 run。OSS v1 retained items 只有 assistant 输出，不虚构用户消息。没有记录的 legacy task 保留摘要并明确不支持；provider 截断、空记录、加载失败与连接中断分别显示。查看不创建、重跑或停止子任务。见 [子任务记录](subagent-history-design.md)。

proposed_plan 保持独立计划正文，查看不触发执行；原生搜索索引仍遵循 prose 边界。长粘贴使用现有富文本转文件和可撤销草稿恢复方案，正文通过附件发送。

### 工作区管理

| 域           | 范围与权限                                                                   | 必须保留的边界                                                                                                                                                                                      |
| ------------ | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Schedule #66 | 机器规则/时区、三种目的地、CRUD、暂停恢复/立即运行、历史和 proposal 审核     | 上游 registry/control 与机器执行；proposal 只有用户确认后创建；未知写入不自动重复创建/执行；无 iOS 后台调度器。                                                                                     |
| Project #67  | local/GitHub 脚本、共享、移除影响、清理结果和 Skills                         | 清理默认关闭；远端预检查后再确认写命令，pending/offline 不静默隐藏；原目录与脏 worktree 保留。GitHub Skills 扫描有上限、跳过 symlink，partial 明示。                                                |
| Provider #68 | 按机器 CRUD、连接验证、模型/认证、安装更新及任务、标题生成                   | 校验新鲜 owner 和版本冲突；受机器 providerSetup/auth/profile 等能力门槛限制；认证通过官方加密输入协议；凭据不进展示快照/App Group/诊断。                                                            |
| Shortcut #69 | 独立 index/body、CRUD/可见性/作用域、稳定 UTF-16 结构化引用、@ 与 slash 发现 | Quick Replies 仍本机，Agent command 仍独立；普通/首条/queue 只展开一次，Steer 不再展开；失效引用在写入前拒绝。网络失败保留当前编辑草稿和 publication IDs；没有新增 kill 后的离线正文缓存/发布恢复。 |
| Team #70     | 成员/邀请/加入申请、角色/移除、退出/所有权转移、服务端限额/费用              | 原生固定官方接口、Keychain 与账号/工作区 fence；owner 受保护，转移需要精确工作区名称确认；完整账单和工作区删除不在本 issue。                                                                        |
| Feedback #71 | 用户填写、环境、可选诊断/最多四张截图、编辑/预览/分享/公开 issue             | 默认不含聊天、账户邮箱、路径和凭据；报告指向 Innei/lody-ios，用户主动提交；截图在 GitHub 手动附加，网络或登录失败可保留/复制完整报告。                                                              |

项目与 Shortcut 细节见 [项目管理](oss-project-management-design.md)、[Prompt Shortcuts](oss-prompt-shortcuts-design.md)。整合所有权和验证要求见 [本轮交付设计](oss-feature-delivery-design.md)。

## 源码与验证入口

路径以仓库根目录为基准；下面列出本轮使用的源码与检查入口。验证结果和未覆盖范围分别登记，不能仅凭检查入口判断验收通过。

| 域                       | 当前源码                                                                                                                                                  | 行为检查 / UI case                                                                                                                                                                  |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Assistant / 创建         | `packages/cloud-runtime/src/runtime/create-session.ts`、`run-options.ts`、`apps/mobile/modules/lody-kit/ios/CreateSession/`                               | `apps/mobile/tests/native/creation-catalog.test.mjs`、`create-session.test.mjs`；`create-parity`、`run-options`、`attachment-create`、`share-probe`                                 |
| 发送 / 队列              | `packages/cloud-runtime/src/runtime/queue.ts`、`session.ts`、`apps/mobile/src/features/sessions/useSessionQueue.ts`、`useSessionSend.ts`                  | `apps/mobile/tests/native/queue-controls.test.mjs`、`session-control.test.mjs`；`send-queue-tools`、`send-queue`、`outbox`、`send`                                                  |
| Fork / pin / 未读 / 归档 | `packages/cloud-runtime/src/runtime/session-tools.ts`、`archive-session.ts`、`apps/mobile/src/features/sessions/autoArchive.ts`                           | `apps/mobile/tests/native/session-tools.test.mjs`、`archive-session.test.mjs`、`apps/mobile/tests/sessions/auto-archive.test.mjs`；`session-tools`、`title-rename`、`inbox`、`home` |
| 搜索 / PR / 计划         | `apps/mobile/src/features/sessions/prepareSessionHistory.ts`、`useProposedPlan.ts`、`apps/mobile/src/cloud/github/pullRequests.ts`                        | `session-search`、`pull-request`、`proposed-plan`、`edit-message`                                                                                                                   |
| Usage / 对话块           | `packages/cloud-runtime/src/protocol/transcript-context.ts`、`agent-usage.ts`、`apps/mobile/modules/lody-kit/ios/Chat/ChatContextCell.swift`              | `apps/mobile/tests/native/transcript-context.test.mjs`、`apps/mobile/tests/cloud/agent-usage.test.mjs`；`usage-context`、`message-details`、`mcp-files`、`rich-paste`               |
| 子任务                   | `packages/cloud-runtime/src/runtime/subagent-history.ts`、`apps/mobile/src/features/subagent-history/`、`SubagentTaskScreen.tsx`                          | `apps/mobile/tests/sessions/subagent-history.test.mjs`；`subagent-history`                                                                                                          |
| Schedule                 | `packages/cloud-runtime/src/runtime/schedules.ts`、`protocol/schedule-time.ts`、`apps/mobile/src/screens/SchedulesScreen.tsx`                             | `apps/mobile/tests/cloud/schedules.test.mjs`；`apps/mobile/verification/ui/schedules.py`                                                                                            |
| Project                  | `packages/cloud-runtime/src/runtime/project-management.ts`、`apps/mobile/modules/lody-kit/ios/Cloud/ProjectManagementCloud.swift`                         | `apps/mobile/tests/native/project-management.test.mjs`、原生 `verification/project-management/`；`project-management`                                                               |
| Provider                 | `packages/cloud-runtime/src/runtime/providers.ts`、`apps/mobile/src/screens/ProviderManagementScreen.tsx`                                                 | `apps/mobile/tests/native/providers.test.mjs`、`apps/mobile/tests/settings/providers.test.mjs`；`providers`                                                                         |
| Shortcut                 | `packages/cloud-runtime/src/runtime/prompt-shortcuts.ts`、`apps/mobile/modules/lody-kit/ios/Cloud/PromptShortcutsCloud.swift`                             | `apps/mobile/tests/native/prompt-shortcuts.test.mjs`；`prompt-shortcuts`、`mentions-production`、共享创建 host                                                                      |
| Team                     | `apps/mobile/modules/lody-kit/ios/Cloud/TeamManagement.swift`、`apps/mobile/src/cloud/team.ts`、`TeamScreen.tsx`                                          | `apps/mobile/tests/team/team.test.mjs`、原生 `verification/team/`；`team`                                                                                                           |
| Feedback / Preview       | `apps/mobile/src/features/feedback/`、`apps/mobile/modules/lody-kit/ios/Feedback/BugFeedback.swift`、`apps/mobile/src/hooks/screens/useSessionPreview.ts` | `apps/mobile/tests/feedback/report.test.mjs`、`apps/mobile/tests/sessions/preview-close.test.mjs`；`feedback`、`preview-close`                                                      |

本轮使用现有托管 Simulator lease、共享 DerivedData 和正常签名，固定 English 软件键盘/离线环境；共享控制覆盖 Chat、CreateSession 与真实 Share host。截图、原生状态及原视频实际时间戳由各域独立审阅，CreateSession 比较的是修改前和最终候选的真实版本。最终记录保留原始失败、完整重跑、执行命令、App 身份、源码和脚本版本，用户验收另行决定。

生产验证仍 pending：公开 Cloud 管理接口、旧/新机器协议、实际认证/安装、真实 Schedule 执行、Git/清理、邀请/退出/转移、通知与 TestFlight 冷启动。当前确定性 fixture 没有向真实账号发邀请、安装运行时、删除目录或自动提交 issue。

## 未覆盖的能力与产品边界

| 状态    | 项                                             | 当前边界                                                                                        |
| ------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| pending | diff / GitHub review 行级评论                  | 尚无独立评论工作流；#15 收口只读 PR/CI，不含 merge 或 review 写操作。                           |
| pending | 岛内批准权限 / push-to-start                   | 当前 Live Activity 与推送入口保留；完整岛内回答、杀进程后的桌面新会话展示需独立设计和设备验收。 |
| pending | 独立 iOS Device Flow client                    | 当前透明使用已注册的 lody-cli；服务端注册前保持现状。                                           |
| wont    | 本机终端 / Monaco / 外部 IDE / 多 Tab IDE      | 属于桌面或机器执行环境；iOS 保留原生导航、远程查看与控制。                                      |
| wont    | 手机直接执行 Git、清理原项目、安装 ACP runtime | 项目/Provider 管理发送官方远程请求，执行在机器端。                                              |
| wont    | 桌面任意 URL IDE 浏览器与 Preview 可视化标注   | 保留已有远程预览、tunnel 与 Simulator preview，不搬桌面 IDE 内嵌浏览器/标注工作流。             |
| wont    | 聊天 PNG 导出、ACP 历史导入执行端              | 当前保留分享与远程历史导入入口；这些桌面专属执行路径不移到手机。                                |

移动端容量仍有明确上限：每个 catalog replica 8 MiB，目录列表等读取有界，partial/truncated/failed 不标 live。凭据留在原生安全边界，不复用桌面凭据，Metro 不导入 `@lody/shared` 根入口；不添加 Android，不自动重放写入，发送不用 `BGContinuedProcessingTask`。

## 怎么刷新对照

1. 读取 OSS 固定 commit 的源码或新 snapshot，登记完整 SHA；不要仅凭本机分支名或旧 checkout 假定当前上游。
2. 核对公开 schema、Cloud/机器协议、具体能力门槛、删除与未知写入语义，再更新本仓路径和 issue 映射。
3. 区分 existing、implemented、未覆盖范围与验证结果；有证据后才更新 pending 和关闭 issue。
4. 追加修订记录，保留之前对照的版本与结论来源。

## 修订

| 日期       | 说明                                                                                                                                                                                                                               |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-09-11 | 初稿，对照 OSS 4400744a 与当时 iOS 工作区。                                                                                                                                                                                        |
| 2026-09-11 | 拆成 GitHub #7–#29，保留父子依赖与上游链接。                                                                                                                                                                                       |
| 2026-09-11 | #11 七类 Mentions 与持久化前 expansion，专项对照 63ae7ad5；原生短引用差异见 Mentions 设计。                                                                                                                                        |
| 2026-09-11 | #8 Worked-for 减去 permissionWaitMs，完成态与 live tick 共用公式。                                                                                                                                                                 |
| 2026-10-12 | 固定 OSS 987962e77022df6a800f4e889f124b51f6eb8056，更新协议源码迁移路径与全部 31 个 open issues 映射；完成 19 项功能和英文双主题手机整合验证，保留 Role/legacy/队列/子任务及真实服务未验证边界。#4/#6/#49 不作为本次新功能完成项。 |
