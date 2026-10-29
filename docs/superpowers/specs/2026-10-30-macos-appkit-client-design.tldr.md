# macOS AppKit 客户端 · TL;DR

完整设计稿：`2026-10-30-macos-appkit-client-design.md`
画布：https://claude.ai/artifact/3LSmrnU2B8LPdJ89dSTdCh

## 要做什么

一个叫 “Lody” 的原生 AppKit Lody Cloud 客户端。作用和 iOS 版一样，数据层和 iOS 共用，UI 用 AppKit 重写。

## 你会看到什么（按阶段）

1. **拆数据层**：iOS 用起来没有任何变化，iOS 的检查全部通过（3–5 天）
2. **改名**：LodyKit 改成 LodyiOSKit（半天）
3. **Mac 第一版**（3–4 周）：
   - 侧栏是 Codex 式结构，会话用原生窗口标签打开
   - transcript 和 iOS 一样是安静的文档流
   - 输入框按 Codex 的样子做；能新建会话、回复、审批权限
   - 支持自定义 accent；关掉窗口后继续同步，有本地通知
4. **分发**：公证过的 .dmg（约 1 天）

## 决定

| 决定                                                          | 来自         |
| ------------------------------------------------------------- | ------------ |
| AppKit，在本仓库新开 target，app 名 “Lody”                    | 你           |
| 只做云端客户端，不在本机跑 agent                              | 你接受了推荐 |
| `LodyData`（共享）+ `LodyMacKit`；LodyKit 改名为 `LodyiOSKit` | 你           |
| 第一版能新建会话、回复、审批权限                              | 你接受了推荐 |
| 布局 q1-c、调性 q2-a 参考 Codex、transcript q3-a              | 你           |
| 中性选中态 + 自定义 accent（q4-a）                            | 你           |
| 输入框照 Codex 截图做（q8）                                   | 你           |
| Codex 式侧栏、原生窗口标签                                    | 你接受了推荐 |

## 请重点检查（我自己做的判断）

- 只有最前面的标签实时显示 transcript；后台标签的状态点来自工作区目录，仍然是实时的
- 通知只覆盖当前工作区；Mac 版不注册 `lody://`，避免和官方桌面版抢这个链接
- iOS 登录流程不变；Mac 用默认浏览器打开授权页
- accent 可选色里没有绿和红，它们留给 diff 的增删和危险操作
- 搬文件按目录分小批，每批单独合入 main
