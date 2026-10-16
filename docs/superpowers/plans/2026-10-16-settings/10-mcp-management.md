# SET-10 完善 MCP 管理并核对使用效果

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第二阶段                               |
| 优先级   | P1                                     |
| 状态     | 待排期                                 |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

使 MCP 列表、默认启用和后续配置操作具有明确语义，并验证它们对会话的真实影响。

## 当前依据

已有 MCP 名称及 enabledByDefault 编辑；运行时保留 connection／bearerToken 等未投影字段，测试覆盖重名拒绝。完整连接管理和设置对会话配置的作用仍需追踪。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/screens/RemoteSettingEditorScreen.tsx](../../../../apps/mobile/src/screens/RemoteSettingEditorScreen.tsx)
- [apps/mobile/src/features/settings/remote-settings.ts](../../../../apps/mobile/src/features/settings/remote-settings.ts)
- [packages/cloud-runtime/src/runtime/settings.ts](../../../../packages/cloud-runtime/src/runtime/settings.ts)
- [packages/cloud-runtime/src/models/settings.ts](../../../../packages/cloud-runtime/src/models/settings.ts)
- [apps/mobile/tests/native/settings.test.mjs](../../../../apps/mobile/tests/native/settings.test.mjs)
- [apps/mobile/verification/ui/settings.py](../../../../apps/mobile/verification/ui/settings.py)

## 工作内容

- [ ] 追踪默认启用设置与新会话／现有会话输入配置的消费路径，明确生效时机。
- [ ] 整理列表的名称、连接类型摘要、默认状态和权限；保持连接秘密不投影到 RN。
- [ ] 核实添加、删除、编辑 transport 和验证连接的正式协议；按可用能力逐步接入。
- [ ] 为新增连接字段保留严格输入校验和原生秘密处理，不用通用 JSON 入口绕过边界。

## 验收标准

- [ ] 修改默认状态后，消费该值的会话路径体现真实结果，而不仅是列表文字变化。
- [ ] 重名、权限拒绝、连接失败、并发修改和保存失败有可恢复反馈。
- [ ] 只改名称／默认状态时保留连接凭据与未知字段。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不因整理 UI 自动运行 MCP 工具或加载远程脚本；完整连接编辑需先有经验证的安全接口。

## 关联任务

[SET-09](./09-agent-management.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
