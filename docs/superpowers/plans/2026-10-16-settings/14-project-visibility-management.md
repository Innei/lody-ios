# SET-14 补齐工作区项目可见性管理

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第三阶段                               |
| 优先级   | P2                                     |
| 状态     | 已排队（已做协议预查）                 |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 已授权按 09 → 13 → 14 → 15 → 16 推进   |

## 目标

补齐截图中“管理哪些本地项目对团队可见”的设置能力，避免和项目首页、历史导入混淆。

## 当前依据

已有项目目录、创建／注册本地项目、目录浏览和历史导入路径；runtime/local-projects.ts 包含 local-project/control 与写入保护，但本轮未核实团队可见性管理协议。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [packages/cloud-runtime/src/runtime/local-projects.ts](../../../../packages/cloud-runtime/src/runtime/local-projects.ts)
- [packages/cloud-runtime/src/models/catalog.ts](../../../../packages/cloud-runtime/src/models/catalog.ts)
- [apps/mobile/src/screens/ProjectScreen.tsx](../../../../apps/mobile/src/screens/ProjectScreen.tsx)
- [apps/mobile/src/screens/ProjectHistoryScreen.tsx](../../../../apps/mobile/src/screens/ProjectHistoryScreen.tsx)
- [apps/mobile/tests/native/local-projects.test.mjs](../../../../apps/mobile/tests/native/local-projects.test.mjs)
- [apps/mobile/src/screens/SettingsScreen.tsx](../../../../apps/mobile/src/screens/SettingsScreen.tsx)

## 工作内容

- [ ] 追踪项目注册、机器归属、团队可见性和移除的真实协议，区分隐藏、解除注册与删除磁盘文件。
- [ ] 提供按机器辨认的项目管理列表和实际支持的可见性操作；项目历史继续保留独立入口。
- [ ] 权限校验在实际写入边界执行；保留不确定 append 结果不重放的现有保护。
- [ ] 明确操作对现有会话、项目目录和其他成员的影响，再设计必要确认。

## 验收标准

- [ ] 可见性改变能由读回或目录消费侧证实；不只是前端隐藏。
- [ ] 非所有者无法管理他人机器项目，工作区切换后不误操作旧 ID。
- [ ] 调整可见性不删除本地文件或会话历史；部分失败与未知结果有明确反馈。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不复用“删除项目”来实现隐藏，不因设置管理扩大磁盘删除能力。

## 关联任务

[SET-08](./08-machine-management.md) · [SET-20](./20-roadmap-closeout.md)

## 2026-10-17 协议预查

已在[官方公开客户端契约](https://github.com/LodyAI/Lody/blob/main/packages/cloud-api/src/index.ts)确认 `localProjects:listVisibleLocalProjects` 与 `localProjects:setLocalProjectSharedWithTeam`。可见性属于云端注册记录，使用工作区、机器和本地项目 ID 定位，不是 `local-project/control` 的删除或目录操作。

下一步将注册记录与当前目录按机器／项目 ID 关联；缺少注册记录时不能推断为“私有”。写入后重新读取真实状态；未完成读回不显示成功，未知写入不自动重放。所有权需在实际云端边界验证，不能只禁用 UI。尚未调用真实云端，也未实现本仓适配。

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
