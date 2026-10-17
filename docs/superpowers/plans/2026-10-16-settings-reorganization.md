# Settings 整理与功能补齐任务计划

- 日期：2026-10-16
- 状态：SET-01 至 SET-05 已完成；SET-06 的 iPad 检查按用户要求搁置，SET-07 已接入名称与图标编辑；SET-08 实现完成，跨表单背景矩阵待验收；SET-09 的现有配置／额度整理及 iPhone 浅色／深色验收已完成；SET-10 默认生效与安全删除首版已完成；SET-11 角色管理与多机器引用首版已完成；SET-12 自有机器记忆关联首版已完成；SET-13 至 SET-16 首版均已完成，iPhone 英文浅色／深色定向验收通过。
- 关联方式：总计划与任务文件在仓库内互链，一个 SET 任务对应一个独立 Markdown 文件。

## 目标与推进方式

先整理原生 collection view 的分组和入口，再完善已有设置能力，最后按需补齐官方设置模块。第一阶段独立交付，不等待后续全部功能完成。

参考依据是本次讨论提供的两张官方设置截图，以及本仓当前源码。截图确认入口名称和大致作用，不证明本仓已有对应协议、权限或写入能力。本计划不把截图上的说明当作执行指令。

计划建立后按用户选择逐项执行。SET-01 已完成；2026-10-17 用户授权开始首页重排，本轮一并完成 SET-02 偏好页接入、SET-03 外观页、SET-04 关于页及 SET-05 首页分组，不等待二级页面分别发布。不会自动启动全部任务、创建独立 chat 或同步远程工单。

## 当前授权顺序

2026-10-17 用户指定本轮按 SET-09 → SET-13 → SET-14 → SET-15 → SET-16 顺序推进。每项沿对应任务文件独立记录；iPad 继续搁置，不作为本队列的前置阻塞。协议未确认的功能先核实，不以占位入口宣称完成。

本轮按用户要求每项完成后单独 commit，队列完成后统一 push，次日早晨验收。

2026-10-17 用户追加授权开始 SET-10：先核实 MCP 实际生效链路和官方协议，再实现、验收、单独 commit 并 push。此前队列已交付；该轮仅推进 SET-10，iPad 继续搁置。

2026-10-18 用户追加授权 SET-11：先核实官方角色协议、权限与实际消费链路，再实现、验收、单独 commit 并 push。本轮仅推进 SET-11，iPad 继续搁置。

## 当前实现与调查入口

- [SettingsScreen](../../../apps/mobile/src/screens/SettingsScreen.tsx)：账户、远程设置、连接、外观、通知、聊天行为、关于、历史与归档入口。
- [LodyGroupedList](../../../apps/mobile/modules/lody-kit/ios/List/LodyGroupedList.swift) 与 [NativeList](../../../apps/mobile/modules/lody-kit/src/list/NativeList.ts)：原生 inset grouped section、标题／footer、说明、菜单、当前值和导航箭头。
- [RemoteSettingsScreen](../../../apps/mobile/src/screens/RemoteSettingsScreen.tsx)、[remote-settings](../../../apps/mobile/src/features/settings/remote-settings.ts) 与 [runtime/settings](../../../packages/cloud-runtime/src/runtime/settings.ts)：机器／Agent／MCP 的读取、有限编辑、缓存、权限及错误恢复。
- [WorkspaceEditorScreen](../../../apps/mobile/src/screens/WorkspaceEditorScreen.tsx)：已有工作区名称和图标编辑；不是完整生命周期管理。
- [UI Verify](../../../apps/mobile/verification/ui/README.md)：已有离线页面场景、模拟器池、英文浅色／深色验证和证据规则。

本轮核实到的首页登录态顺序是：账户 → 会话 → 工作区 → 连接 → 外观 → 通知 → 聊天 → 关于 → 开发。主要问题是入口、具体选项和状态混用一个层级，并非缺少原生分组能力。

历史 [OSS 对齐文档](../../oss-alignment.md) 可作调查线索，但不能直接复用其中旧日期的完成状态。每个任务开工前按当前源码和正式公开协议重新核对。

## 第一阶段的分组契约

下图只包含第一阶段可落地的已有能力：

```text
设置
├── 账户卡片（独立 section，无重复标题）
│   └── 头像、名称、邮箱 → 账户详情
├── 个人
│   ├── 偏好设置
│   └── 外观
├── 工作区 · 当前工作区名称
│   ├── 机器
│   ├── Agents
│   ├── MCP
│   └── 离线时：重新同步
│       footer：真实连接状态与最后同步时间
├── 会话与记录
│   ├── 项目历史
│   └── 已归档会话
├── 其他
│   ├── 关于
│   └── 诊断
└── 开发（仅 __DEV__ 或 uiVerify）
    └── Debug
```

| 首页入口   | 二级内容                                                 | 所属任务                                                         |
| ---------- | -------------------------------------------------------- | ---------------------------------------------------------------- |
| 账户卡片   | 现有名称、邮箱及退出登录                                 | [SET-05](2026-10-16-settings/05-home-sections-and-connection.md) |
| 偏好设置   | 通知与实时活动入口；会话行为组含队列／引导和本机快捷回复 | [SET-02](2026-10-16-settings/02-preferences-page.md)             |
| 外观       | 深色背景、强调色、App 图标                               | [SET-03](2026-10-16-settings/03-appearance-page.md)              |
| 工作区     | 当前机器、Agents、MCP 入口与连接反馈                     | [SET-05](2026-10-16-settings/05-home-sections-and-connection.md) |
| 会话与记录 | 保留现有历史导入和归档行为                               | [SET-05](2026-10-16-settings/05-home-sections-and-connection.md) |
| 关于       | 版本、构建号、开源许可                                   | [SET-04](2026-10-16-settings/04-about-page.md)                   |
| 诊断       | 保留范围选择、导出和清空                                 | [SET-05](2026-10-16-settings/05-home-sections-and-connection.md) |

分组规则：

1. 一个逻辑分组对应一个原生 section；导航行只代表入口，具体选项由二级页面拥有。
2. 首轮沿用 UIKit inset grouped 布局、系统语义色、透明导航栏与原生滚动边缘。只有证明现有 API 无法表达时才修改共享列表。
3. 首页个人入口使用简短功能说明；具体当前值放二级设置项。导航有箭头，菜单有菜单指示，纯信息不伪装操作。
4. 账户卡片已登录时打开现有账户页；未登录显示真实欢迎状态，不新增无效登录操作。
5. 工作区和会话记录依赖有效的当前工作区；已登录但无工作区保留工作区说明 section，隐藏无效导航行和会话记录，不能进入后立即空白退出。账户切换与工作区切换隔离数据。
6. 连接状态跟随工作区：正常／同步中使用 footer，离线保留可点击恢复动作与缓存语义。机器数量不等于在线数量。
7. 首轮不迁移存储、不改变默认值、不新增云端同步、不放尚未完成的占位入口。历史与归档暂时单独成组。
8. 首页继续沿用现有 Settings sheet 和内部原生 push；不在本轮改成新的 Tab、全屏路由或第二套 Modal 管理器。

## 官方入口覆盖与缺口

“已有”表示源码中存在能力，不代表本轮重新做过运行验收；“待核实”表示需要先查明正式协议，不能据此推断服务端不支持。

| 官方入口         | 本仓当前依据                               | 计划处理                         | 任务                                                                                                                   |
| ---------------- | ------------------------------------------ | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 账户             | 信息展示与退出登录                         | 首轮归位；不顺带增加资料编辑     | [SET-05](2026-10-16-settings/05-home-sections-and-connection.md)                                                       |
| 偏好设置         | 通知／实时活动、发送行为、本机快捷回复已有 | 先收拢入口，再逐项评估缺口       | [SET-02](2026-10-16-settings/02-preferences-page.md)、[SET-19](2026-10-16-settings/19-personal-settings-gap-review.md) |
| 外观             | 深色背景、强调色、App 图标；语言文案已有   | 先收拢；语言／文字等按需决定     | [SET-03](2026-10-16-settings/03-appearance-page.md)、[SET-19](2026-10-16-settings/19-personal-settings-gap-review.md)  |
| 工作区通用       | 菜单已有改名、图标编辑                     | 接设置入口；生命周期另核实       | [SET-07](2026-10-16-settings/07-workspace-general.md)                                                                  |
| 机器             | 列表、改名、所有权校验                     | 核对状态、管理边界和可支持操作   | [SET-08](2026-10-16-settings/08-machine-management.md)                                                                 |
| Agents           | 机器分组、名称／prompt 编辑、额度窗口      | 整理并补有正式协议的操作         | [SET-09](2026-10-16-settings/09-agent-management.md)                                                                   |
| Agent 角色       | 已接角色管理与 v2 多机器引用               | 首版完成；完整配置编辑在电脑端   | [SET-11](2026-10-16-settings/11-agent-roles.md)                                                                        |
| 记忆             | 已核实设备级身份／关联协议                 | 自有机器首版已完成               | [SET-12](2026-10-16-settings/12-memory-management.md)                                                                  |
| MCP              | 默认值接入发送，名称／默认编辑与安全删除   | 首版完成；完整连接编辑在电脑端   | [SET-10](2026-10-16-settings/10-mcp-management.md)                                                                     |
| Prompt Shortcuts | 本机快捷回复已有；不是同一能力             | 接工作区模型与提及消费路径       | [SET-13](2026-10-16-settings/13-prompt-shortcuts.md)                                                                   |
| 项目             | 目录、注册、历史导入已有                   | 核实并补团队可见性管理           | [SET-14](2026-10-16-settings/14-project-visibility-management.md)                                                      |
| GitHub           | PR 读取与评论已有                          | 核实连接与仓库授权管理           | [SET-15](2026-10-16-settings/15-github-integration-settings.md)                                                        |
| AI 用量          | 单条消息 Token、供应商额度已有             | 核实聚合统计、费用与团队趋势     | [SET-16](2026-10-16-settings/16-ai-usage.md)                                                                           |
| 分享             | 静态副本发布与 Keychain 凭据已有           | 核实我的／团队分享列表与撤销     | [SET-17](2026-10-16-settings/17-published-shares-management.md)                                                        |
| 关于             | 版本与许可已有                             | 收到二级页面                     | [SET-04](2026-10-16-settings/04-about-page.md)                                                                         |
| 报告 Bug         | 本机诊断导出已有                           | 建立真实反馈渠道，日志由用户选择 | [SET-18](2026-10-16-settings/18-bug-reporting.md)                                                                      |

保留本仓特有的项目历史、归档、诊断和开发入口。工作区 Prompt Shortcuts 与本机快捷回复、工作区用量与订阅额度、静态分享管理与 Share Extension 收件箱各自独立，不以改名替代缺失功能。

## 任务索引

任务编号是稳定标识，不代表必须按数字顺序串行执行。状态仅在实际完成工作、记录证据后更新；一个任务只有下表中的一个主文件。

| 任务                                                                                              | 阶段／优先级       | 状态                         | 前置任务                                                                                                                                                                                                                     |
| ------------------------------------------------------------------------------------------------- | ------------------ | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [SET-01 确定分组契约并采集改动前基线](2026-10-16-settings/01-section-contract-and-baseline.md)    | 第一阶段／P0       | 已完成                       | 无                                                                                                                                                                                                                           |
| [SET-02 建立偏好设置页并迁移现有行为选项](2026-10-16-settings/02-preferences-page.md)             | 第一阶段／P0       | 已完成                       | [SET-01](2026-10-16-settings/01-section-contract-and-baseline.md)                                                                                                                                                            |
| [SET-03 建立外观页并迁移现有外观选项](2026-10-16-settings/03-appearance-page.md)                  | 第一阶段／P0       | 已完成                       | [SET-01](2026-10-16-settings/01-section-contract-and-baseline.md)                                                                                                                                                            |
| [SET-04 建立关于页并整理版本与许可入口](2026-10-16-settings/04-about-page.md)                     | 第一阶段／P0       | 已完成                       | [SET-01](2026-10-16-settings/01-section-contract-and-baseline.md)                                                                                                                                                            |
| [SET-05 重排 Settings 首页并归位连接状态](2026-10-16-settings/05-home-sections-and-connection.md) | 第一阶段／P0       | 已完成                       | [SET-01](2026-10-16-settings/01-section-contract-and-baseline.md)、[SET-02](2026-10-16-settings/02-preferences-page.md)、[SET-03](2026-10-16-settings/03-appearance-page.md)、[SET-04](2026-10-16-settings/04-about-page.md) |
| [SET-06 完成首轮分组整理的集成验收](2026-10-16-settings/06-phase-one-acceptance.md)               | 第一阶段／P0       | iPad 暂缓                    | [SET-02](2026-10-16-settings/02-preferences-page.md)、[SET-03](2026-10-16-settings/03-appearance-page.md)、[SET-04](2026-10-16-settings/04-about-page.md)、[SET-05](2026-10-16-settings/05-home-sections-and-connection.md)  |
| [SET-07 接入工作区通用设置](2026-10-16-settings/07-workspace-general.md)                          | 第二阶段／P1       | 已完成（名称／图标）         | [SET-05](2026-10-16-settings/05-home-sections-and-connection.md)                                                                                                                                                             |
| [SET-08 完善机器设置的展示与管理边界](2026-10-16-settings/08-machine-management.md)               | 第二阶段／P1       | 实现完成（背景矩阵待验收）   | [SET-05](2026-10-16-settings/05-home-sections-and-connection.md)                                                                                                                                                             |
| [SET-09 完善 Agents 设置与现有额度展示](2026-10-16-settings/09-agent-management.md)               | 第二阶段／P1       | 已完成（配置／额度整理）     | [SET-05](2026-10-16-settings/05-home-sections-and-connection.md)                                                                                                                                                             |
| [SET-10 完善 MCP 管理并核对使用效果](2026-10-16-settings/10-mcp-management.md)                    | 第二阶段／P1       | 已完成（默认生效／安全删除） | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-11 补齐 Agent 角色管理入口](2026-10-16-settings/11-agent-roles.md)                           | 第三阶段／P2       | 已完成（首版）               | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-12 补齐记忆管理入口](2026-10-16-settings/12-memory-management.md)                            | 第三阶段／P2       | 已完成（首版）               | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-13 补齐工作区 Prompt Shortcuts](2026-10-16-settings/13-prompt-shortcuts.md)                  | 第三阶段／P2       | 已完成（首版）               | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-14 补齐工作区项目可见性管理](2026-10-16-settings/14-project-visibility-management.md)        | 第三阶段／P2       | 已完成（首版）               | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-15 补齐 GitHub 连接与仓库管理设置](2026-10-16-settings/15-github-integration-settings.md)    | 第三阶段／P2       | 已完成（首版）               | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-16 补齐工作区 AI 用量统计](2026-10-16-settings/16-ai-usage.md)                               | 第三阶段／P2       | 已完成（首版）               | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-17 补齐已发布分享管理](2026-10-16-settings/17-published-shares-management.md)                | 第三阶段／P2       | 已完成（首版）               | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-18 建立报告 Bug 流程并复用诊断导出](2026-10-16-settings/18-bug-reporting.md)                 | 第三阶段／P2       | 待排期（提交渠道待确定）     | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-19 补齐移动端适用的偏好与外观缺口](2026-10-16-settings/19-personal-settings-gap-review.md)   | 第三阶段／P2       | 待排期（逐项定范围）         | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |
| [SET-20 核对设置功能覆盖并整理交付记录](2026-10-16-settings/20-roadmap-closeout.md)               | 收口／按里程碑执行 | 待收口                       | [SET-06](2026-10-16-settings/06-phase-one-acceptance.md)                                                                                                                                                                     |

## 执行顺序与依赖

第一阶段：

```text
┌──────────────────────────────┐
│ SET-01 分组契约与改动前基线   │
└──────────────┬───────────────┘
               ▼
┌──────────────────────────────┐
│ SET-02 偏好设置               │
│ SET-03 外观                   │
│ SET-04 关于                   │
│ 三个页面可分别推进            │
└──────────────┬───────────────┘
               ▼
┌──────────────────────────────┐
│ SET-05 首页重组与连接归位      │
└──────────────┬───────────────┘
               ▼
┌──────────────────────────────┐
│ SET-06 首轮集成验收           │
└──────────────┬───────────────┘
               ▼
     ◆ 第一阶段达到验收？ ◆
          │是          │否
          ▼            └───> 回到失败项所属任务
┌──────────────────────────────┐
│ 首轮可交付；选择后续任务      │
└──────────────────────────────┘
```

第二阶段建议先 [SET-07](2026-10-16-settings/07-workspace-general.md)，复用工作区编辑能力；再按需要选择 [SET-08](2026-10-16-settings/08-machine-management.md)、[SET-09](2026-10-16-settings/09-agent-management.md)、[SET-10](2026-10-16-settings/10-mcp-management.md)。它们不必为了相邻编号而互相等待。

第三阶段 [SET-11](2026-10-16-settings/11-agent-roles.md) 至 [SET-19](2026-10-16-settings/19-personal-settings-gap-review.md) 按真实需求选择，每项先核实协议和权限，再定最小实现范围。角色与 Agents、快捷指令与 composer、分享与诊断的关联属于复用与集成关系，不默认要求其他路线图任务先全部完成。

[SET-20](2026-10-16-settings/20-roadmap-closeout.md) 在每次选定批次收口时更新记录。它只硬依赖第一阶段验收；只有要宣称整个官方设置功能已补齐时，才要求所有后续项都有完成证据或明确的范围决策。

## 实施与数据边界

- 遵循 [AGENTS.md](../../../AGENTS.md)。开工前检查工作树、全部调用方、测试、fixture、配置与导出；保留用户已有修改。
- 页面使用现有 definePage／usePageRuntime／present，二级浏览使用 push；需要结果的临时表单使用既有 present 契约。
- 列表使用 LodyGroupedList／UICollectionViewListCell。导航选择态按原生返回转场恢复，取消交互返回时还原；不得在 snapshot completion 重选旧行。
- 本机偏好沿现有持久化路径；云端数据沿 data-runtime 和现有 Keychain 边界。RN 不新增 live replica。
- 云端任务必须核实正式公开的 RN-safe subpath／协议；不得导入 Lody root entry、另一个 checkout 的绝对路径或私有后端包。
- 密码、长期凭据和 secret 不进入 RN、WebView、诊断或 fixture；不确定写入结果不得自动重放。
- 远程权限校验、冲突检测、失败保留草稿和账户／工作区隔离属于功能范围，不因首版简化省略。
- 若改动 ChatComposerView／CreateSession 的共享路径，验证所有受影响宿主；改新会话表单前先做 create-parity 基线与 parity-diff 对照。
- 原生新增／删除文件后按仓库要求运行 pods；生成 ios 文件不得成为唯一持久修改位置。

## 验证与交付

每个任务自己的验收是完成条件，集成任务补全跨页链路。没有可用正式接口时记录调查结论和恢复条件，不能把调查完成等同于功能完成。

1. **静态检查**：实际代码改动运行 pnpm check、pnpm bundle 和 git diff --check。新逻辑补小而有效的行为测试；不为常量表或 section 顺序写实现快照。
2. **原生构建**：使用 pnpm verify:build，保留签名。构建及多检查流程用 pnpm verify:simulator --name '<本次验收名>' -- <command>；在租赁流程内将 $LODY_VERIFY_UDID 传给所需检查。独立本地检查省略 --udid，由工具租赁验证设备。共享 DerivedData，不直接创建 Simulator。
3. **离线 UI**：新增／更新场景使用真实生产组件，注入确定性 service／数据；经 UI.open_case 进入。默认字号，英文 en／en_US，浅色和深色，不另做中文 pass。
4. **按改动选择检查面**：页面分组与入口迁移只检查该页排版、入口、原生返回和迁移选项的持久化，不逐项重跑目标页面的完整业务流程。上述页面能力在 SET-06 按实际集成影响选择检查；iPad 仅在改动影响其宿主时复查。新增 settings-baseline 记录不同作用域的原排版。
5. **视觉与交互**：视觉状态截图，导航、菜单及转场视频；实际审阅分组间距、文字截断、当前值、滚动边缘、44 pt 触控和 VoiceOver。超时或缺失场景判失败。
6. **协议与写入**：测试公开行为、权限拒绝、缓存恢复、保存冲突、未知结果和账户切换。离线 fixture 不真实授权 GitHub、不发布分享、不提交反馈。
7. **交付记录**：更新对应任务的实现范围、验证命令、构建与证据路径、未跑项及原因；再更新总计划状态。缺失操作不能写成“已补齐”。
8. **发现其他问题**：与当前排版／入口变更无关的既有缺陷单独记录，不顺手修改共享控件并据此扩大当前任务的回归范围。

## 当前范围决策与待核实项

- 已决定：先分组、后功能；保留原生列表；个人在工作区前；具体选项迁入二级页；已有功能保持可达。
- 已在 SET-01 确认：会话与记录单独一组；连接正常放 footer，离线有恢复行；无工作区只显示说明，具体规则和既有行映射见任务文件。
- 待核实：生命周期、完整机器／Agent／MCP 管理、记忆的团队授权与创建／编辑、Prompt Shortcuts、项目可见性、GitHub 授权管理、聚合用量和分享管理协议。
- 待按需决定：个人资料编辑、App 内语言／文字设置的必要性、报告 Bug 渠道；不自动扩大为本计划全部必做能力。
- 不做：桌面 Terminal 设置、Android、额外 live replica、通用 JSON 配置编辑器、未完成入口占位。
- 不估算未经调查的工期；每个协议任务查明后再给出实际工作量和顺序调整。

## 本次文档交付记录

- 2026-10-16：建立总计划和 20 个任务文件，登记文件、依赖、范围和验收；App 实现未开始。
- 文档质量检查：交付前校验本地文件链接、任务一对一映射、依赖无环、格式和工作树状态。运行结果在本次 chat 的交付说明中记录。

- 2026-10-16：完成 SET-01 的分组契约、17 行迁移归属、作用域盘点与六状态双外观基线。仅新增离线验证支持，产品排版未迁移；后续从 SET-02／03／04 选择推进。

- 2026-10-17：按用户授权开始实际首页重排，一并接入偏好、外观、关于；验证仅覆盖设置分组、迁移选项和入口返回，不扩展聊天、模型或 Share Extension 回归。

- 2026-10-17：完成 SET-02 至 SET-05。正式首页已接入偏好、外观、关于；pnpm check、pnpm bundle 与设置范围的英文浅深色检查通过。复用原签名 Debug app，未新增原生改动；未运行 iPad 或业务全流程，SET-06 保留集成收口。证据：`.artifacts/settings-reorder/`。

- 2026-10-17：用户要求先搁置 iPad，直接接入 SET-07。SET-06 的剩余 iPad 检查不阻塞本项；只接入已有工作区名称与图标编辑，不扩展生命周期或其他业务回归。

- 2026-10-17：SET-07 已接入工作区“通用”，复用原编辑表单与写入服务。pnpm check、pnpm bundle、9 个 cloud 行为检查及独立 workspace-general 英文浅深色检查通过；生命周期操作保持暂缓，未运行 iPad 或其他业务全流程。

- 2026-10-17：SET-08 补机器 ID、真实 presence、只读和缓存说明，沿用改名及权限／冲突边界。13 项设置行为检查和机器页英文浅深色检查通过。按用户追加要求沿设置子页排查背景，修复远程设置、工作区通用和快捷回复三个表单宿主；五类表单的完整视觉矩阵受并行 Expo 58／RN 0.88 升级和原生生成过程阻塞，保留待验收，不扩展业务全流程。

- 2026-10-17：SET-13 Prompt Shortcuts、SET-14 项目可见性、SET-15 GitHub 和 SET-16 AI 用量首版完成，按任务单独 commit。工作区入口顺序为通用 → 机器 → Agents → MCP → Prompt Shortcuts → 项目 → GitHub → AI 用量。
- 本轮[设置验收证据](https://app.lobehub.com/acceptance/49fe2ad2-5420-4cb5-a9a1-abb2e3f8203c)：4/4 项、iPhone 英文浅色／深色共 8/8 场景通过，148 份证据上传完成，截图与录像无缺失。覆盖只读、失败原稿／确认值保留、刷新与读回，以及用量旧范围迟到隔离。
- 程序化检查：8 项定向行为检查、31 项 UI runner 检查、TypeScript、i18n、原生源登记、许可证、bundle 与带签名 Release 模拟器构建通过。全仓 `pnpm check` 仅在并行任务的 `wide-layout-design.md` 格式处失败；本轮保留该任务文件及其他在途改动。
- 首版边界：复杂快捷模板只读；GitHub 个人授权在官方网页完成；AI 用量只展示工作区汇总与趋势，费用标为预估。未执行真实云端修改、GitHub 授权或统计对账，iPad 按用户要求搁置。

- 2026-10-17：SET-10 完成官方协议核对与默认生效／安全删除首版。首次发送采用工作区默认值，续聊和队列保留既有选择，删除的 ID 在后续发送前过滤；连接缺失、冲突、权限拒绝与未知写入有恢复边界，连接秘密不进入 RN。
- 本轮 [MCP 验收](https://app.lobehub.com/acceptance/5eccf834-f0a1-40f2-8265-f01da5fa0df9?r=1)：2/2 项、66 份证据上传完成。MCP 与五类共享表单的英文浅色／深色共 4/4 场景通过，55 项相关行为检查、31 项 UI runner 检查、bundle 及带签名 Release 模拟器构建通过；全仓 check 仍仅受另一任务的宽屏设计文档格式影响。
- SET-10 边界：新增服务器及完整连接编辑由电脑端完成，工具发现正式接口限本机 RPC；未做真实 Cloud 修改、MCP 连接／工具、iPad 或物理设备验证。详见[任务记录](2026-10-16-settings/10-mcp-management.md)。

- 2026-10-18：SET-11 核实官方 v1／v2 Flock 协议、所有者／可见性与 Streams 写权限，接入角色创建、公共字段编辑、分享和删除；保留原目标／模型／模式／记忆配置。引用补齐多机器目标、全工作区在线发现及发送前重验。
- 角色管理、聊天引用和新会话表单引用的 iPhone 英文浅色／深色 6/6 场景通过；52 项相关行为检查、31 项 UI runner 检查、全仓 check、bundle 与正常签名 Release 模拟器构建通过。原有未提交改动保留。
- SET-11 边界：完整目标／运行配置编辑仍在电脑端；private 仅控制可信客户端发现，不提供工作区存储机密性。未做真实 Cloud 角色修改、远程角色会话／MCP 工具、iPad 或物理设备验证。详见[任务记录](2026-10-16-settings/11-agent-roles.md)。

- [SET-11 验收](https://app.lobehub.com/acceptance/772f0d2a-3989-4cd4-b6fd-6bd8c1baed74?r=1)：角色管理、原生引用和权限／消息载荷；验证范围及边界见任务记录。

- 2026-10-18 用户授权 SET-12 调查、实现、验收后独立 commit 并 push；iPad 继续搁置。记忆首版限自有机器的身份列表／来源／状态／详情、确认导入与解除关联，正文由 provider 持有；角色绑定和 provider 创建／更新仍在电脑端。权限链、实际 ACP 环境注入与边界见[任务记录](2026-10-16-settings/12-memory-management.md)。

- [SET-12 验收](https://app.lobehub.com/acceptance/cbe06440-b213-48f0-b311-2d7e64c59055?r=1)：身份管理、可用性与权限／数据边界 3/3 项，130 份证据上传完成；iPhone 英文浅色／深色 4/4 流程通过。29 项运行时行为检查、31 项 UI runner 检查、全仓 check、完整 runtime 类型检查、bundle 与正常签名 Release 构建通过。首版边界和真实 Cloud／nmem／插件未验范围见任务记录。

- 2026-10-18：用户授权开始 SET-17。核对官方静态分享 DTO、分页、服务端范围和撤销版本号，接入摘要列表／详情、原生打开／复制及确认撤销；客户端首版验收完成，原有工作树改动保留。[SET-17 验收](https://app.lobehub.com/acceptance/77c60b8a-ca15-4fe2-aadd-38b5470b4ca9?r=1)：管理、可用性与权限、原生凭据／写入边界 3/3 项，105 份证据上传完整；新增 4/4 流程和原分享 2/2 回归通过。真实 Cloud 与真机范围见任务记录。
