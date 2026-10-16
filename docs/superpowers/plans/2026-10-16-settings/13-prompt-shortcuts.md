# SET-13 补齐工作区 Prompt Shortcuts

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第三阶段                               |
| 优先级   | P2                                     |
| 状态     | 已排队（已做协议预查）                 |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 已授权按 09 → 13 → 14 → 15 → 16 推进   |

## 目标

提供可复用 Prompt 与提及的工作区管理入口，并和现有本机快捷回复保持清楚边界。

## 当前依据

本机 QuickRepliesProvider 使用原生本地偏好保存 label／message；这不是已验证的工作区 Prompt Shortcuts 同步协议。现有 mentions 可作为消费路径调查起点。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/features/settings/quick-replies.tsx](../../../../apps/mobile/src/features/settings/quick-replies.tsx)
- [apps/mobile/src/features/settings/quickReplies.ts](../../../../apps/mobile/src/features/settings/quickReplies.ts)
- [apps/mobile/src/screens/QuickRepliesScreen.tsx](../../../../apps/mobile/src/screens/QuickRepliesScreen.tsx)
- [packages/cloud-runtime/src/models/mentions.ts](../../../../packages/cloud-runtime/src/models/mentions.ts)
- [apps/mobile/src/screens/SettingsScreen.tsx](../../../../apps/mobile/src/screens/SettingsScreen.tsx)

## 工作内容

- [ ] 核实 Prompt Shortcuts 的 ID、内容结构、提及展开规则、可见性、权限和持久化协议。
- [ ] 决定工作区列表与最小编辑／创建范围；不迁移、不覆盖本机快捷回复数据。
- [ ] 明确在聊天／新会话中如何选择和展开，复用实际存在的 composer 与 mentions 边界。
- [ ] 在长度、空内容、引用失效、权限变化和冲突处保留输入校验与草稿。

## 验收标准

- [ ] 快捷回复与工作区 Prompt Shortcuts 两类数据互不覆盖，切换工作区不会改变本机回复。
- [ ] 实际插入／发送内容与所选 shortcut 一致；被撤销访问的提及不能继续展开私有内容。
- [ ] 保存失败保留草稿，内容和提及的长度边界有行为检查。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不将纯字符串模板冒充支持完整提及语义；改共享 composer 时覆盖每个受影响宿主。

## 关联任务

[SET-02](./02-preferences-page.md) · [SET-11](./11-agent-roles.md) · [SET-20](./20-roadmap-closeout.md)

## 2026-10-17 协议预查

已找到[官方公开客户端契约](https://github.com/LodyAI/Lody/blob/main/packages/cloud-api/src/index.ts)：`promptShortcuts` 提供目录发现、分资源授权、staging、activate、settle 和撤销。正文并不在普通工作区目录中；索引按所有者与 private／workspace 分域，正文使用独立文档授权。不能用现有工作区 grant 读取私有正文。

本地参考源码还确认正文是 Loro 文档，包含 revision ancestry 和原子保存的 prompt／mentions；索引是 Flock。现有纯文本 mention 展开不能直接代替这套语义。下一步先接入原生认证与 scoped grant，再做目录／正文读写、冲突与撤销边界，最后接设置页和聊天消费。首版不迁移本机快捷回复。尚未调用真实云端，也未实现本仓适配。

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
