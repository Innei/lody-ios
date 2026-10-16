# SET-12 补齐记忆管理入口

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第三阶段                               |
| 优先级   | P2                                     |
| 状态     | 待排期（协议待核实）                   |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

按官方实际记忆模型展示可访问记忆及来源设备，再按协议支持范围增加管理操作。

## 当前依据

提供的官方截图有“记忆”入口；本轮未确认本仓存在可直接复用的记忆管理协议。现有 Swift／runtime 的缓存或模型选择记忆不能等同于该功能。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/screens/SettingsScreen.tsx](../../../../apps/mobile/src/screens/SettingsScreen.tsx)
- [packages/cloud-runtime/src/models/settings.ts](../../../../packages/cloud-runtime/src/models/settings.ts)
- [packages/cloud-runtime/src/runtime/settings.ts](../../../../packages/cloud-runtime/src/runtime/settings.ts)
- [apps/mobile/src/cloud/settings.ts](../../../../apps/mobile/src/cloud/settings.ts)

## 工作内容

- [ ] 查明公开 schema／接口、导入来源、机器归属、所有权、分页以及内容敏感性；将证据写回本任务。
- [ ] 确定首版最小范围：列表、来源与状态、详情；只有确认写接口后才纳入修改／删除／导入。
- [ ] 通过现有 runtime 与原生凭据边界接入；按账户／工作区／机器隔离缓存。
- [ ] 在无数据、离线缓存、无权限、来源设备失联时显示明确状态。

## 验收标准

- [ ] 同名记忆可按稳定 ID 和来源设备区分；账户切换不显示上一用户内容。
- [ ] 详情只展示有权限内容；读取失败不伪装成空列表。
- [ ] 若纳入删除／导入，检查确认、取消、失败与重复提交边界。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

没有已验证的协议时只完成调查并保留任务状态，不添加空入口、不读取手机外部私有记忆文件。

## 关联任务

[SET-11](./11-agent-roles.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
