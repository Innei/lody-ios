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
