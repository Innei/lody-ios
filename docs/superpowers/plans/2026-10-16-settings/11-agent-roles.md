# SET-11 补齐 Agent 角色管理入口

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第三阶段                               |
| 优先级   | P2                                     |
| 状态     | 待排期（管理协议待核实）               |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

提供工作区 Agent 角色的管理入口，复用已有角色读取和授权规则，并接回实际使用路径。

## 当前依据

runtime/agent-roles.ts 已读取 agentRole，按 private／workspace 可见性及 machine／agent 关联做校验；不能将这条读取路径视为完整管理 API。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [packages/cloud-runtime/src/runtime/agent-roles.ts](../../../../packages/cloud-runtime/src/runtime/agent-roles.ts)
- [packages/cloud-runtime/src/models/mentions.ts](../../../../packages/cloud-runtime/src/models/mentions.ts)
- [apps/mobile/modules/lody-kit/ios/CreateSession/CreateSessionController.swift](../../../../apps/mobile/modules/lody-kit/ios/CreateSession/CreateSessionController.swift)
- [apps/mobile/src/screens/SettingsScreen.tsx](../../../../apps/mobile/src/screens/SettingsScreen.tsx)

## 工作内容

- [ ] 核实角色 schema、revision 冲突、所有权、可见性及创建／修改／删除的正式写入路径。
- [ ] 先列可访问角色及其所属机器／Agent、可见性和只读原因；使用稳定 ID 处理同名角色。
- [ ] 仅对已验证的操作提供表单，保留权限和版本冲突处理。
- [ ] 追踪新会话、续聊、@role 等现有消费者，验证新增或编辑后的角色可以被正确使用。

## 验收标准

- [ ] 私有角色不跨用户泄露，工作区角色可见性符合权限；不存在的机器／Agent 不形成可执行角色。
- [ ] 冲突、无权限和写入结果不明不被当成成功；不重复写入。
- [ ] 实际消费侧使用角色 ID 并读取最新授权内容，不让 UI 注入未经验证的角色指令。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不为管理页重建一份 RN live replica；如触及共享新会话表单，执行 create-parity 前后对照及各宿主检查。

## 关联任务

[SET-09](./09-agent-management.md) · [SET-13](./13-prompt-shortcuts.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
