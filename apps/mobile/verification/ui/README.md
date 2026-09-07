# Offline UI verification

All UI baselines run without login, user data, cloud credentials, or a connected
machine. `EXPO_PUBLIC_UI_VERIFY=1` in a **development** bundle prevents account
restoration before Keychain/SQLite reads and disables login. The runner starts
its own Metro and requires the `ui-verify-ready` marker before any interaction.
Native image fixtures additionally require the `--ui-verify` launch argument and
compile only in Debug. No production credentials are seeded or erased.

## Run locally

Build the normal signed Debug app (`pnpm ios`), or generate assets before a direct
`xcodebuild`. Create a disposable iPhone 17 Pro / iOS 26.5 Simulator; do not pass
your everyday Simulator. Local and CI runs use the same entry points:

```sh
xcrun simctl create 'Lody Offline UI' com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5
xcrun simctl boot SIMULATOR_UDID
xcrun simctl bootstatus SIMULATOR_UDID -b
pnpm verify:native --udid SIMULATOR_UDID
pnpm verify:ui --udid SIMULATOR_UDID --app /absolute/path/to/Lody.app
```

Requires Python 3, AXe 1.8.0, Xcode 26.5 and the workspace dependencies.
`--case layout` selects one case (still both appearances). `--port 8098` changes
the isolated Metro port; occupied ports are rejected. `--output PATH` selects an
artifact directory; use a new path for each run. The runner owns only its Metro
process group and the supplied app process. A small host-only CoreSimulator helper disconnects hardware keyboard input for
the supplied device so keyboard geometry is actually tested. No global Simulator
preferences are changed. Remove the disposable Simulator when finished. It never shuts down another Simulator or Metro.

## Baseline inventory

| Case             | Production surface                        | Behavior                                                                                                                  |
| ---------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| home             | NativeTabs + InboxScreen + creation Sheet | 首页导航栏搜索、已归档结果、取消恢复；右下角新建反复打开并保留当前 Tab                                                    |
| send             | NativeChat + shared send lifecycle        | Offline immediate user/shiny rows, no pre-connection dispatch, failed text/attachment restoration, receipt reconciliation |
| send-handoff     | NativeComposer sheet → NativeChat push    | Message UIView stays visible across navigation before creation; failed creation restores draft in target input            |
| layout           | NativeChat + navigation title             | Stream segments, completion folding, full conclusion, process-row height, send positioning                                |
| tracking         | NativeChat                                | User drag releases following, stable history, return button during/after streaming                                        |
| model-options    | ChatComposerView                          | Model/effort controls, RN echo, reopen persistence                                                                        |
| image-preview    | ChatImageCell + ChatImagePreview          | Synthetic bitmap, zoom/restore, button and gesture dismissal                                                              |
| composer         | NativeComposer in a real form sheet       | Keyboard clearance, pending draft clearing, rejection restore, duplicate suppression                                      |
| composer-success | NativeChat composer                       | Pending clear/lock, text and attachment stay cleared after acceptance                                                     |
| markdown         | MarkdownView code block                   | Copy preserves complete code and indentation through the Simulator clipboard                                              |
| background       | DataRuntime + BGContinuedProcessingTask   | 同一 WebView 跨后台恢复、真实系统申请、完成/到期释放；系统拒绝时明确记录未验证长时执行                                    |
| changes          | NativeChat + file diff page               | Grouped file rows after completion, header totals, long paths, direct diff navigation, hidden warnings                    |
| inbox            | NativeGroupedList + inboxSections         | 动态分组；会话行是对话列表（标题前进行中圆点、时间在右、确认胶囊）；未读完成不进今天                                      |
| composer-failure | NativeChat composer                       | Exact text and attachment restoration after rejection                                                                     |

Every case starts a fresh app process and navigates from Debug. Both light and
dark appearances run with default text size and English system controls. Fixture
content remains Chinese. Composer requests remain pending until the driver taps
Complete Request, so request timing cannot hide the busy state. These scenes
exercise production native draft contracts; they do not claim to cover cloud
persistence or Machine RPC. Those retain their existing behavior tests.

`verify:native` reuses chat, watchdog, local-store, status-label rendering,
composer, attachment and diff-font checks. The former ChatMarkdown-specific drawing and
block-selection tests referenced a deleted renderer and have been retired;
Markdown is rendered by the actual chat baseline, with screenshots/video for
review. There is no pixel-diff gate yet: screenshots are evidence, not automatic
proof of typography or animation quality.

## CI and future UI changes

`.github/workflows/verify.yml` runs Checks and Offline iOS UI on PRs and pushes to
main. Configure both as required checks in the repository branch rules before
relying on them to block merges. UI artifacts contain results.json, per-case
logs, screenshots, accessibility trees and video, including failures. Missing
scenes and timeouts fail the job. No login or distribution signing secret is used.

For each new UI behavior:

1. Add/reset a deterministic scene under development-only Debug. Reuse production
   views and the existing `present` contract; inject data or service outcomes at
   the owning boundary. Do not duplicate a production screen into a fake UI.
2. Add a runnable user-visible assertion and register it in the runner. New scenes
   must run independently on a fresh Simulator, without earlier cases or login.
3. Reproduce bugs with the original precondition; avoid internal constant-table
   snapshots. Prefer element-relative geometry and bounded state waits.
4. For shared UI, exercise each real host (e.g. chat and creation sheet). Add
   navigation/return integration cases when those boundaries change.
5. Review screenshots for appearance changes and video for keyboard/scroll/gesture
   changes. Baseline updates require review; never auto-approve a failed comparison.

Settings details, product catalog navigation and live cloud workflows are not
covered by these chat-focused baselines yet. Their future UI changes must add
independent offline module scenes under the same contract.

后台用例通过 `--case background` 运行，模拟器 Home 停留 40 秒。计数来自真实离屏 WebView 回调；云端事件用本地脚本代替，不访问网络或凭据。若系统拒绝持续后台任务，该用例仅验证保留/恢复与申请失败降级，不能据此宣称后台长时执行已通过。长时间真机网络连接和能耗另需实测。

`--case home` 使用独立的 `EXPO_PUBLIC_UI_VERIFY_HOME=1` 开发包，在 Auth/Catalog Provider 边界注入内存数据，不启动认证或同步。完整运行会先以独立 Metro 运行该场景。新建只验证打开和取消；未绑定电脑的项目不读取电脑配置、不发送真实消息。
