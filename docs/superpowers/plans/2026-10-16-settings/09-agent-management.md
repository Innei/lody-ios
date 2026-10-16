# SET-09 完善 Agents 设置与现有额度展示

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第二阶段                               |
| 优先级   | P1                                     |
| 状态     | 待排期                                 |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

整理按机器分组的 Agent 配置、编辑能力与额度说明，并明确和 Agent 角色的区别。

## 当前依据

已有按机器分组的 Agent 列表、名称与 prompt 编辑，以及供应商订阅额度窗口。远程模型不向 RN 投影 env／secret，现有测试验证保留未知字段和秘密。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/features/settings/remote-settings.ts](../../../../apps/mobile/src/features/settings/remote-settings.ts)
- [apps/mobile/src/features/settings/agent-usage.ts](../../../../apps/mobile/src/features/settings/agent-usage.ts)
- [apps/mobile/src/screens/RemoteSettingsScreen.tsx](../../../../apps/mobile/src/screens/RemoteSettingsScreen.tsx)
- [apps/mobile/src/screens/RemoteSettingEditorScreen.tsx](../../../../apps/mobile/src/screens/RemoteSettingEditorScreen.tsx)
- [packages/cloud-runtime/src/runtime/settings.ts](../../../../packages/cloud-runtime/src/runtime/settings.ts)
- [apps/mobile/tests/native/settings.test.mjs](../../../../apps/mobile/tests/native/settings.test.mjs)
- [apps/mobile/tests/cloud/agent-usage.test.mjs](../../../../apps/mobile/tests/cloud/agent-usage.test.mjs)
- [apps/mobile/verification/ui/settings.py](../../../../apps/mobile/verification/ui/settings.py)

## 工作内容

- [ ] 保持机器分组，明确 Agent 配置的来源、只读原因和供应商额度含义。
- [ ] 核对官方支持字段与当前 name／prompt 编辑边界；逐项决定是否补，不默认扩展任意 JSON 编辑。
- [ ] 核实新增、删除、启用等管理协议；需要秘密输入的能力留在经过验证的原生安全边界。
- [ ] 保留额度的缓存／离线、未知重置时间和自定义 API 不适用等状态。
- [ ] 在名称与说明中区分 Agents、Agent 角色和工作区 AI 用量。

## 验收标准

- [ ] 不同机器上的同名 Agent 不混淆，权限和缓存按用户／工作区／机器正确隔离。
- [ ] 保存修改不覆盖 env 和未知字段；敏感内容不进入 RN、日志、fixture 或诊断。
- [ ] 额度缺失、离线、重置时间未知均不显示为零消费或实时结果。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

首版不做通用 Agent 配置编辑器；订阅额度不作为 Token 费用统计。

## 关联任务

[SET-11](./11-agent-roles.md) · [SET-16](./16-ai-usage.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
