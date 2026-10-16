# SET-17 补齐已发布分享管理

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第三阶段                               |
| 优先级   | P2                                     |
| 状态     | 待排期（列表与撤销协议待核实）         |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

在设置中管理已发布的静态会话副本，复用现有分享发布流程与凭据存储。

## 当前依据

已有静态分享发布、协议校验、原生会话分享表单和 Keychain reader credentials；工作区列表、管理员查看全部分享、撤销等能力尚未核实。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/cloud/session-sharing.ts](../../../../apps/mobile/src/cloud/session-sharing.ts)
- [packages/cloud-runtime/src/models/session-sharing.ts](../../../../packages/cloud-runtime/src/models/session-sharing.ts)
- [packages/cloud-runtime/src/runtime/sharing/runtime.ts](../../../../packages/cloud-runtime/src/runtime/sharing/runtime.ts)
- [packages/cloud-runtime/src/runtime/sharing/README.md](../../../../packages/cloud-runtime/src/runtime/sharing/README.md)
- [apps/mobile/modules/lody-kit/ios/SessionShare/LodySessionShareView.swift](../../../../apps/mobile/modules/lody-kit/ios/SessionShare/LodySessionShareView.swift)
- [apps/mobile/verification/ui/session-share.py](../../../../apps/mobile/verification/ui/session-share.py)
- [apps/mobile/src/screens/SettingsScreen.tsx](../../../../apps/mobile/src/screens/SettingsScreen.tsx)

## 工作内容

- [ ] 核实我的分享／工作区分享列表、分页、访问权限、过期、撤销及删除的公开协议。
- [ ] 复用现有发布对象身份与 Keychain 读取边界；列表只展示允许公开的摘要。
- [ ] 明确静态副本的生成时间及其与原会话的关系，提供支持的打开、复制、撤销等操作。
- [ ] 管理员可见范围必须来自服务端；不通过本地发布历史推断工作区全部分享。

## 验收标准

- [ ] 私有 reader credentials 不进入列表投影、URL 日志或诊断；退出和账号切换后不显示旧分享。
- [ ] 撤销／删除若纳入，读回真实状态；失败保留可重试入口，不自动重复发布。
- [ ] 管理流程复用静态副本，不把分享变成持续同步；离线 UI 验证不真实发布。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

这里的“分享”指发布副本管理，与 iOS Share Extension 收件箱、单条消息导出分开。

## 关联任务

[SET-18](./18-bug-reporting.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
