# SET-20 核对设置功能覆盖并整理交付记录

[总计划](../2026-10-16-settings-reorganization.md) · [任务索引](../2026-10-16-settings-reorganization.md#任务索引)

| 字段     | 内容                                   |
| -------- | -------------------------------------- |
| 阶段     | 收口                                   |
| 优先级   | 按里程碑执行                           |
| 状态     | 待收口                                 |
| 依赖     | [SET-06](./06-phase-one-acceptance.md) |
| 当前授权 | 编写计划；实现尚未开始                 |

## 目标

保持总计划与实际实现一致，明确每个官方入口是已支持、部分支持还是暂缓，并为选定批次提供可核查交付记录。

## 当前依据

本计划建立的是可逐项选择的路线图；第一阶段可以先完成，后续任务的真实能力依赖重新核实协议与权限。

以下是本轮确认的调查入口；开工前重新检查工作树、调用方、导出、fixture 和配置。新增文件及协议以实施时的证据为准。

- [apps/mobile/verification/ui/README.md](../../../../apps/mobile/verification/ui/README.md)
- [docs/oss-alignment.md](../../../../docs/oss-alignment.md)
- [AGENTS.md](../../../../AGENTS.md)

## 工作内容

- [ ] 按已选批次检查总计划覆盖矩阵与各任务验收记录；未实施的任务保持未完成，不由索引勾选代替行为证据。
- [ ] 对已交付模块记录支持范围、协议来源、权限、验证命令／构建及截图视频路径。
- [ ] 只在重新核实相关能力后更新旧对齐文档；不把过期的 docs/oss-alignment.md 状态当作当前事实。
- [ ] 记录暂缓项、阻碍和恢复条件，保证首页不出现失效或虚假完成的入口。
- [ ] 检查文档链接、工作树与索引，清理仅属本批次的临时文件；提交／PR／push 依用户后续要求执行。

## 验收标准

- [ ] 每个 SET 任务只对应一个主文件，总计划与任务依赖双向可追溯。
- [ ] 阶段一验收不等待全部后续模块；要声明“官方截图功能全部补齐”时，SET-07 至 SET-19 每项必须有完成证据或明确范围决策。
- [ ] 部分支持与未知结果明确列出，未运行的检查不被写成通过。

执行总计划的[验证与交付规则](../2026-10-16-settings-reorganization.md#验证与交付)。新分支、错误恢复、权限与持久化逻辑要有小而有效的行为检查；只有静态分组搬迁不新增实现快照。

## 范围边界

不为完成文档打勾而扩大实现范围；本任务不默认授权发布、创建远程 issue 或独立 Codex chat。

## 关联任务

[SET-07](./07-workspace-general.md) · [SET-08](./08-machine-management.md) · [SET-09](./09-agent-management.md) · [SET-10](./10-mcp-management.md) · [SET-11](./11-agent-roles.md) · [SET-12](./12-memory-management.md) · [SET-13](./13-prompt-shortcuts.md) · [SET-14](./14-project-visibility-management.md) · [SET-15](./15-github-integration-settings.md) · [SET-16](./16-ai-usage.md) · [SET-17](./17-published-shares-management.md) · [SET-18](./18-bug-reporting.md) · [SET-19](./19-personal-settings-gap-review.md)

## 实施记录

- 开始日期：未开始。
- 协议／范围结论：待实施时填写；未知能力不视作已有接口。
- 验证与证据：未运行。
- 未解决问题：见工作内容中的待核实项；完成时补充实际结果。
