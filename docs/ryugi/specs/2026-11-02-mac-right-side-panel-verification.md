# Mac Right Side Panel 验证记录

设计：[已批准说明](2026-11-02-mac-right-side-panel-design.md)。
原生截图与录像：[Artboard Verify](https://ryugi.innei.dev/a/crWbKWeAn87N8BZBJ2GkC?page=verify)。

- `pnpm mac:build`：通过，保持正常签名。
- `pnpm verify:mac:vm --case inspection --case core-parity --in-process`：266 项通过，0 失败；真实操作与浅深色截图保存在 `.artifacts/mac-verify-vm`。
- `MacInspectionReviewTests`：10 项通过；包含最后补充的 Quick Look 装入窗口、切回 Changes 后关闭标签的生命周期检查。此项在上述 VM 批次后添加，用相同产品代码在离屏 hosted target 验证。
- `pnpm verify:mac --case inspection --case core-parity`：通过。
- `pnpm verify:simulator --name 'Mac inspector shared diff' -- pnpm verify:build`：iOS Simulator 签名构建通过。
- `pnpm verify:native --case inline-diff`：共享 Diff 算法、布局与语义颜色检查通过。
- `swift test --package-path packages/lody-core`：18 项通过。
- `pnpm test`、`pnpm bundle`、`git diff --check`：通过。
- `pnpm check`：类型、协议、本地化、原生源码和许可证检查通过；全仓 Prettier 未通过，涉及 213 个已有或本地 Artifacts 文件。未对无关文件批量格式化。本次提交的 Markdown、YAML、TypeScript 格式检查通过。
- 完整 `pnpm verify:native`：未通过，既有 `session-feed` 独立编译脚本没有包含 `DiagnosticsStore` 输入；本次没有改动这一边界。

最终审阅发现并修正：单文件点击路径与变更汇总丢失、工作区切换失败沿用历史列表、取消后的列表恢复、原生会话标签暂停与恢复、PDF 类型识别、附件下载文件的所有权。也覆盖了四个并发读取的上限、长 Diff 行完整横向滚动、等待 runtime 就绪，以及加载中关闭再打开文件。没有延期的审阅问题。

实施中的两项取舍：

1. 分栏接线与真实数据模型在第二阶段一起完成；布局验证因此后移一阶段，现已覆盖 760 / 1100 pt。
2. Foundation-only 的 iOS `InlineDiffModel.swift` 由 Xcode 源码成员关系复用，未迁移到 LodyData；如以后抽成包，需要迁移源码位置与对应构建输入。

功能提交：`1335437`、`87c1fa0`、`bfa824f`、`b7922f9`、`0e0b00e`；设计提交：`6fce3cc`。本次未推送。

Verify 页的四组视觉验收等待用户判断。截图和录像均来自无头 VM 或离屏 App，未操作宿主机屏幕、指针或键盘。

## 用户否决后的原生 UI 重写

上一版的视觉实现被用户明确否决。重写保留已验证的 scoped 数据读取，重新实现全部 inspector 呈现层：标题栏内的文件标签、45 pt 工具栏、文件头与分隔线、行号栏、上下文与 hunk 展开、原生预览、图片背景、按需文件树，以及聊天中的变更分组。

离线场景改用批准稿的九个文件和同一张参考图片，避免占位内容干扰视觉比较。旧截图复制到 Artboard 的 `pages/verify/before-*`；新截图与录像在原四组中替换，不修改批准稿。

独立回归检查覆盖了标题栏承载、筛选不切换比较范围或预取其他文件、弹层与会话暂停时的视图生命周期、行号栏不遮挡代码首字，以及显示其余 hunks 不重新请求机器。代码和 Diff 都用 22 pt 行高。

首轮完整 VM 检查 `inspection + core-parity + in-process`：272 通过，0 失败。随后检查截图发现启动时的窗口恢复会干扰第一个宽窗口截图，UI case 改为启动后用 inbox 建立场景并断言 1440 × 900；同时修正查找条打开和新文件标签显露时的位置。

`pnpm test`、`pnpm bundle`、签名 iOS Simulator 构建、共享 inline-diff 原生检查均通过。`pnpm check` 的类型、协议、本地化、源码成员关系和许可证均通过；最后的全仓格式检查仍有 209 个已有或本地 Artifacts 文件警告。本次 TS/JSON 文件的单独格式检查通过。

最终产品代码的 `inspection + in-process` VM 复核：271 项通过，0 失败。包含标题栏内标签、真实文件树与图片缩放、系统查找、760 pt 最小窗口和 1440 × 900 三栏截图。额外核对了代码与行号的基线对齐。

## C · 收敛圆角 UI Polish

2026-11-02 的 Artboard 选择为 `polish-rounded`。原生标签改为 34 pt 高、7 pt 圆角、13 pt 系统字体，最大宽度 198 pt；选中态为独立内容表面和细边框，临时标签保持斜体。关闭按钮在选中、悬停和键盘聚焦时显示，隐藏时保留其布局空间。文件区缩窄或切换选择后完整显露当前标签及关闭按钮。

截图检查确认：工具栏的系统空格会在分栏压缩时缩小，自定义空白 item 又会带来额外控件边距。最终把前后导航和侧栏开关放在同一个固定布局容器，内部保留两组原生玻璃效果与 12 pt 间距；侧栏开关仍进入原有 Workspace 行为。宽→窄→宽回归测试约束实际控件位置，避免只检查 item 常量表。现有导航状态测试改为通过可访问标识查找控件，保留筛选、折叠后的启用状态断言。

- `MacInspectionLayoutTests`：5 项通过；窄文件区关闭按钮、缩窄后选中项显露、工具栏间距回归均先观察失败再修到通过。
- 全部离屏 `LodyMacTests`：272 项通过，0 失败。
- `pnpm verify:mac:vm --case inspection --in-process`：273 项通过，0 失败。真实点击覆盖侧栏隐藏与恢复、文件标签、760 pt 图片关闭及左邻文件恢复，包含浅深色截图。
- Mac 构建、签名 iOS Simulator 构建、`pnpm test` 和 `pnpm bundle`：通过。
- `pnpm check`：类型、协议、本地化、源码成员关系和许可证检查通过；最后的全仓格式检查仍报告 216 个已有或本地 Artifacts 文件。此次修改的 Markdown 和 Mac 字符串 JSON 已单独检查通过。

[C · 原生对照](https://ryugi.innei.dev/a/crWbKWeAn87N8BZBJ2GkC?page=verify-polish) 保留已选设计稿、原生浅深色截图、760 pt 窗口、侧栏展开和真实交互录像；两组视觉验收等待用户判断。旧设计轮与旧验收页保留。
