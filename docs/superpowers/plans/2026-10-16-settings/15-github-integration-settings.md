# SET-15 补齐 GitHub 连接与仓库管理设置

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 第三阶段                               |
| 优先级   | P2                                     |
| 状态     | 已排队（已做协议预查）                 |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 已授权按 09 → 13 → 14 → 15 → 16 推进   |

## 目标

增加 GitHub 集成的状态与仓库管理入口，复用已有云端认证边界。

## 当前依据

已有 GitHub PR 读取和评论调用；它证明会话中的 PR 能力存在，不能证明 App 已有 GitHub App 安装、授权或仓库管理页面。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/src/cloud/github/pullRequests.ts](../../../../apps/mobile/src/cloud/github/pullRequests.ts)
- [apps/mobile/src/screens/PullRequestScreen.tsx](../../../../apps/mobile/src/screens/PullRequestScreen.tsx)
- [apps/mobile/src/screens/SettingsScreen.tsx](../../../../apps/mobile/src/screens/SettingsScreen.tsx)
- [packages/cloud-runtime/src/models/pull-request.ts](../../../../packages/cloud-runtime/src/models/pull-request.ts)

## 工作内容

- [ ] 查明 GitHub 连接由个人还是工作区拥有，核实 GitHub App／OAuth 安装、回调、仓库列表及管理权限。
- [ ] 首版显示真实连接状态、可访问仓库与权限说明；授权／重授权／移除仅按公开支持能力接入。
- [ ] 回调使用现有路由和认证流程，失败或取消返回设置；不把凭据带入 URL 或诊断。
- [ ] 核对连接变化后 PR 等消费者的缓存失效与错误反馈。

## 验收标准

- [ ] 取消授权、过期授权、无仓库权限和账号切换均不会显示为已连接。
- [ ] 仓库访问范围来自真实授权；移除或权限撤销后消费侧停止访问。
- [ ] 测试 fixture 不调用真实 GitHub 授权或发评论，必要线上验证单独记录范围。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不要求用户在 RN 中粘贴长期 Token，不用现有 PR 成功作为仓库管理完成证据。

## 关联任务

[SET-14](./14-project-visibility-management.md) · [SET-20](./20-roadmap-closeout.md)

## 2026-10-17 协议预查

已在[官方公开客户端契约](https://github.com/LodyAI/Lody/blob/main/packages/cloud-api/src/index.ts)找到工作区仓库状态查询、仓库启用设置和 GitHub App 安装 state；个人操作授权另有 `missing`／`authorized`／`expired` 状态与偏好设置。App 仓库范围与个人身份必须分别显示。

现有 LodyKit 的 GitHubCloud 已有 Keychain → 官方 JWT → Convex 调用边界，可复用认证过程，不向 RN 投影凭据。安装返回目标目前公开为 web／desktop，iOS 回跳尚未确认；未确认前不伪造已授权或添加不工作的回调。下一步先实现真实状态与仓库列表，再按已确认能力接操作和返回刷新。尚未调用真实授权或改动仓库权限。

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
