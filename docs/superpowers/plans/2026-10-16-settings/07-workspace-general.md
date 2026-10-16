# SET-07 接入工作区通用设置

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第二阶段                               |
| 优先级   | P1                                     |
| 状态     | 待排期                                 |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

在工作区组补“通用”入口，先复用已有名称与图标编辑，再根据公开协议确定生命周期操作。

## 当前依据

WorkspaceEditorScreen 已有名称和图标修改，使用 AuthProvider 的更新能力；Settings 首页尚未包含通用入口。截图中的生命周期操作是否可用，尚未核实。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/screens/WorkspaceEditorScreen.tsx](../../../../apps/mobile/src/screens/WorkspaceEditorScreen.tsx)
- [apps/mobile/src/cloud/auth/AuthProvider.tsx](../../../../apps/mobile/src/cloud/auth/AuthProvider.tsx)
- [apps/mobile/src/screens/SettingsScreen.tsx](../../../../apps/mobile/src/screens/SettingsScreen.tsx)
- [apps/mobile/verification/ui/home.py](../../../../apps/mobile/verification/ui/home.py)

## 工作内容

- [ ] 追踪工作区菜单现有编辑调用与权限，再决定直接复用编辑页或增加只有必要摘要的通用页。
- [ ] 显示当前工作区身份；名称和图标修改使用原有服务，保存后各入口立即反映。
- [ ] 核实角色、管理员权限和名称／图标更新失败；旧请求不得更新切换后的工作区。
- [ ] 单独核实退出／归档／删除等生命周期公开协议和业务后果，逐项记录可实现或暂缓；不凭截图设计接口。

## 验收标准

- [ ] 改名与图标更新成功能读回；保存失败不伪装成功，已有草稿保留。
- [ ] 切换工作区后操作仍指向原始明确目标，不误改新工作区。
- [ ] 无权限者不能提交修改；危险生命周期操作若纳入，必须有真实权限、确认和失败恢复检查。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不会默认把删除工作区列为首版必做项；已有编辑能力可以先交付，不等待生命周期接口。

## 关联任务

[SET-05](./05-home-sections-and-connection.md) · [SET-20](./20-roadmap-closeout.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
