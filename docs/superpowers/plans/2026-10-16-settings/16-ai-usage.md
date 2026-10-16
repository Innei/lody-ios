# SET-16 补齐工作区 AI 用量统计

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第三阶段                               |
| 优先级   | P2                                     |
| 状态     | 待排期（统计接口待核实）               |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

建立口径清楚的 Token、预估费用与团队趋势入口，避免把供应商订阅额度当成消费统计。

## 当前依据

Agent 页已有额度窗口；消息详情也展示单条 Token 信息。两者均不是已确认的工作区聚合统计、费用和团队趋势接口。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/features/settings/agent-usage.ts](../../../../apps/mobile/src/features/settings/agent-usage.ts)
- [apps/mobile/src/features/sessions/messageDetails.ts](../../../../apps/mobile/src/features/sessions/messageDetails.ts)
- [packages/cloud-runtime/src/models/agent-usage.ts](../../../../packages/cloud-runtime/src/models/agent-usage.ts)
- [packages/cloud-runtime/src/protocol/agent-usage.ts](../../../../packages/cloud-runtime/src/protocol/agent-usage.ts)
- [apps/mobile/tests/cloud/agent-usage.test.mjs](../../../../apps/mobile/tests/cloud/agent-usage.test.mjs)
- [apps/mobile/src/screens/SettingsScreen.tsx](../../../../apps/mobile/src/screens/SettingsScreen.tsx)

## 工作内容

- [ ] 核实统计接口、时间范围／时区、用户／工作区口径、缓存／推理 Token 分类、费用来源和管理员权限。
- [ ] 先实现有可靠来源的最小汇总，再按接口支持扩展趋势和团队明细；未提供费用时明确不可用。
- [ ] 显示数据截止时间、估算标识、单位、币种及离线／部分失败状态。
- [ ] 复用现有额度显示，保持独立语义和入口关系，不扫描本机会话凑出不完整的团队总数。

## 验收标准

- [ ] 汇总与服务端读回或可信 fixture 对账，边界时间和部分数据不会重复计数。
- [ ] 未知费用不显示为 0，预估不显示为实际账单，额度比例不显示为 Token 消费比例。
- [ ] 成员权限不会泄露他人明细；工作区切换时旧请求和缓存正确隔离。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不硬编码推测单价或把现有聊天记录求和当成完整用量。

## 关联任务

[SET-09](./09-agent-management.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
