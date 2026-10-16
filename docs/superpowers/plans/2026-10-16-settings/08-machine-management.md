# SET-08 完善机器设置的展示与管理边界

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第二阶段                               |
| 优先级   | P1                                     |
| 状态     | 待排期                                 |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

让机器页清楚表达机器身份、状态及可管理范围，并补齐实际协议支持的高价值操作。

## 当前依据

远程设置已列机器并允许有权限者改名，运行时测试覆盖 owner 校验。机器在线状态、目录成员与管理操作需沿实际数据来源核对。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/screens/RemoteSettingsScreen.tsx](../../../../apps/mobile/src/screens/RemoteSettingsScreen.tsx)
- [apps/mobile/src/screens/RemoteSettingEditorScreen.tsx](../../../../apps/mobile/src/screens/RemoteSettingEditorScreen.tsx)
- [apps/mobile/src/features/settings/remote-settings.ts](../../../../apps/mobile/src/features/settings/remote-settings.ts)
- [packages/cloud-runtime/src/runtime/settings.ts](../../../../packages/cloud-runtime/src/runtime/settings.ts)
- [packages/cloud-runtime/src/models/settings.ts](../../../../packages/cloud-runtime/src/models/settings.ts)
- [apps/mobile/tests/native/settings.test.mjs](../../../../apps/mobile/tests/native/settings.test.mjs)
- [apps/mobile/tests/settings/remote-settings.test.mjs](../../../../apps/mobile/tests/settings/remote-settings.test.mjs)
- [apps/mobile/verification/ui/settings.py](../../../../apps/mobile/verification/ui/settings.py)

## 工作内容

- [ ] 明确机器目录、在线 presence、所有权分别来自哪里；不要用 catalog 中机器总数推断在线数量。
- [ ] 整理列表标题、机器标识、只读说明、缓存和同步时间，保留名称编辑。
- [ ] 核实移除／断开／重新授权等公开操作、影响范围和机器版本条件；仅接入明确支持的操作。
- [ ] 读写沿现有 data runtime，保留冲突检测、服务端权限和不确定写入不自动重放的约束。

## 验收标准

- [ ] 同名机器可辨认；离线缓存带清楚状态，失败不被标记为 live。
- [ ] 非所有者不能写入；冲突和保存失败不丢草稿。
- [ ] 选中行返回与交互取消行为正确；新管理动作若纳入，覆盖成功、权限拒绝及不确定结果。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不远程运行系统命令，不新增机器心跳保活，不承诺尚未确认的机器管理 API。

## 关联任务

[SET-09](./09-agent-management.md) · [SET-14](./14-project-visibility-management.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
