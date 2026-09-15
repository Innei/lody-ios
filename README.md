# PR #37 导航工具栏残影 — 验收证据

服务于 [Innei/lody-ios#37](https://github.com/Innei/lody-ios/pull/37)（`fix/navigation-toolbar-ghosting`）。

## 文件

| 文件 | 说明 |
| --- | --- |
| `light-run.mp4` / `dark-run.mp4` | 原始录屏，HEVC，1206×2622，约 32s |
| `light-run-h264.mp4` / `dark-run-h264.mp4` | 同内容 H.264 版本，便于在浏览器中播放 |
| `light-run.gif` / `dark-run.gif` | 10fps 动图，便于在 PR 评论里直接查看 |
| `light-pushed-0.png` / `dark-pushed-0.png` | push 进入会话后的静止帧：首页搜索栏未残留在聊天输入框上 |
| `light-search-active.png` / `dark-search-active.png` | 返回首页后搜索控件仍可正常激活 |

## 场景

离线 Debug 构建、iPhone 模拟器、英文、默认字号，由 `apps/mobile/verification/ui/navigation-toolbar.py` 驱动：

1. 首页 → push 进入会话，校验首页搜索框没有覆盖聊天输入框；
2. 侧滑取消返回，仍停留在会话页；
3. 完成返回，回到首页；
4. 重复第 1–3 步；
5. 激活搜索并输入，确认往返后搜索控件仍可用。

浅色与深色各一轮完整录屏保存在此；PR 描述记录浅色与深色各跑两轮均通过。
验收不涉及真实账号、云端或真机。
