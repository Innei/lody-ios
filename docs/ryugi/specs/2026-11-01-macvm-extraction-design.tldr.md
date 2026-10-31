# macvm TL;DR

完整设计：https://ryugi.innei.dev/a/4QH7Qn90wpMMorr4y7G1u（批准后另存为 `2026-11-01-macvm-extraction-design.md`）

## 做什么

把 `verification/mac/vm*.py` 抽成独立的命令行工具 `macvm`（仓库 `~/git/innei-repo/macvm`）。base VM 所有项目共用，每个项目只需要一份 `macvm.toml`，并有自己的 runner。

## 你会看到什么

1. Lody 里照常运行 `pnpm verify:mac:vm --case sidebar`，结果和现在一样。
2. 宿主机升级 Xcode 后，下一次运行先自动增量更新 base（会多等 10–20 分钟），然后正常运行测试。
3. 新项目接入：写一份 `macvm.toml`，然后运行 `macvm run`。
4. XCUITest 做不到的事，AI 通过 `macvm exec -- cliclick …` 或 `macvm screenshot` 直接操作 runner。
5. 打开 VNC 看 runner，不会出现权限弹窗；Dock 只有 4 个图标，壁纸是纯灰色。

## 决定

| 决定 | 谁定的 |
| --- | --- |
| base 所有项目共用，每个项目一台 runner | 你 |
| base 跟着 Xcode、SDK、工具的变化自动更新 | 你 |
| 独立 CLI，放在自己的仓库 | 你 |
| Homebrew、cliclick、peekaboo 作为兜底工具 | 你 |
| VM 里不出现需要人点的权限弹窗，靠预写权限库实现 | 你 |
| 被测 App 默认不预授权，每次运行前清回"未决定" | 你 |
| 项目配置用 `macvm.toml` | 你同意了推荐 |
| 同时最多 2 台 VM，停掉空闲最久的 | 你同意了推荐 |
| 改成中性名字，一次性迁移，不重装 | 你同意了推荐 |

## 重点看这几条（我自己做的决定）

- base 更新采用"先复制、成功后再替换"，失败不影响正在用的 base
- 新增 `up`、`exec`、`screenshot` 命令，都不拿锁
- 两层锁，不同项目的验证可以同时跑
- 宿主机构建固定使用 base 里那个版本的 Xcode，本期不支持 Xcode beta
- 新仓库不迁移 git 历史

## 时间

大约 6–8 小时：搬代码和加配置层 3–4 小时，迁移和权限预授权约 2 小时，完整验证约 1 小时。
