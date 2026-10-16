# SET-19 补齐移动端适用的偏好与外观缺口

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第三阶段                               |
| 优先级   | P2                                     |
| 状态     | 待排期（逐项定范围）                   |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

在结构整理后，逐项评估截图提及的主题、语言、界面和会话文字设置，补有实际用途的移动端能力。

## 当前依据

已有本机外观、通知／实时活动、发送行为、快捷回复和 en／zh-Hans 文案。i18n 在启动时选择 catalog；是否需要 App 内语言入口及其切换方式尚未决定。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/lib/i18n/index.ts](../../../../apps/mobile/src/lib/i18n/index.ts)
- [apps/mobile/src/lib/i18n/boot.ts](../../../../apps/mobile/src/lib/i18n/boot.ts)
- [apps/mobile/src/lib/theme/appearance.tsx](../../../../apps/mobile/src/lib/theme/appearance.tsx)
- [apps/mobile/src/screens/NotificationSettingsScreen.tsx](../../../../apps/mobile/src/screens/NotificationSettingsScreen.tsx)
- [apps/mobile/modules/lody-kit/ios/Chat/ChatMarkdownTheme.swift](../../../../apps/mobile/modules/lody-kit/ios/Chat/ChatMarkdownTheme.swift)
- [apps/mobile/locales/en.json](../../../../apps/mobile/locales/en.json)
- [apps/mobile/locales/zh-Hans.json](../../../../apps/mobile/locales/zh-Hans.json)

## 工作内容

- [ ] 按现有用户需求盘点主题跟随系统、语言、会话文字等差异，写清当前默认行为和实际需求。
- [ ] 优先采用系统已有的每 App 语言／文字行为；仅在明确需要时新增 App 内设置与持久化。
- [ ] 逐项记录本机范围或账户同步范围，不把“个人”标签误当成已存在的云端同步能力。
- [ ] 每次只接入一项已有明确使用场景的能力；若改共享聊天渲染，覆盖聊天与相关预览。

## 验收标准

- [ ] 修改后真实消费页面生效，重启恢复和取消行为正确；旧偏好不丢失。
- [ ] 系统自动深浅色和辅助功能行为保持有效；UI Verify 仍只运行英文浅色／深色。
- [ ] 语言若纳入，原生／RN 文案和导航标题切换行为一致，未支持的即时切换不伪装生效。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不新增桌面 Terminal 显示设置、不为大字号引入特殊 remount 方案、不一次铺满偏好选项。

## 关联任务

[SET-02](./02-preferences-page.md) · [SET-03](./03-appearance-page.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
