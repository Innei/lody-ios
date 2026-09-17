# 会话搜索：Inbox 正文摘录 + 会话内 find

跟踪 [#44](https://github.com/Innei/lody-ios/issues/44)。上游列表同样不扫正文；有用的是打开会话后的 transcript find。本仓两头都没有「按内容找」的入口。

## 问题

Inbox `searchSections` 只对 catalog 标题和项目名做本地子串匹配。`Session` 没有消息体。打开过的会话会把展示 envelope 写进 SQLite KV（`session:[user,workspace,id]`），长按预览读这份缓存，但列表搜索不用它。会话页没有 find。

用户按说过的话搜，结果永远空。KV 不是领域库，也不该为此改成 `entries` / `items` 表。catalog 仍是整包投影；消息真相源仍是 Loro，打开会话才 bootstrap。

## 目标

同一期交付两套入口，检索由原生做：

1. Inbox / iPad 侧栏：会话仍是一行。正文命中时副标题换成摘录。点进去跳到第一条命中，打开 find 条，不自动弹键盘。
2. 会话内：更多菜单「查找」打开 UIKit find 条。只搜当前已加载的散文。

正文只覆盖这台设备打开过、且成功写入 session 缓存的会话。标题、项目名、路径、分支仍覆盖 catalog 里的全部会话。零命中时把这条边界写进空状态。

## 决定

| 项             | 选择                                                                                                                             |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Inbox 命中形态 | 会话一行；仅当标题/项目/路径/分支都未命中、正文命中时，副标题换成摘录                                                            |
| 点进会话       | 带上 `findQuery`，滚到第一条并高亮，find 条打开，键盘不弹                                                                        |
| 索引范围       | 与上游 `session-chat-search.ts` 一致：`text` 与 `thought`。不索引 tool、plan checklist、subagent、system_notice、文件/图片元数据 |
| 未缓存会话     | 不后台拉历史。空结果说明内容搜索只覆盖本机打开过的会话                                                                           |
| 入口           | 更多菜单「查找」；Inbox 带词则自动打开 find 条                                                                                   |
| 存储           | KV 快照不动。写入 session 缓存时抽出散文到旁路表。不用 FTS5、Spotlight、`UIFindInteraction`                                      |
| 匹配           | Foundation `localizedStandardContains`（大小写/变音/中文按系统 locale）                                                          |
| 未加载历史     | 不计入总数，不自动翻页。用户再加载更早页时重跑计数                                                                               |

## 所有权

原生拥有：抽取、旁路表、Inbox 检索、会话内 find 条、高亮与滚动。

RN 拥有：`UISearchController` 输入（现有 SearchBar）、用 catalog 画行（菜单、pin、归档、徽章）、`sessionNav` 打开会话、更多菜单项。

JS `searchSections` 不再做匹配。它只消费原生 hits，从 catalog 生成现有 `NativeListRow`。`inboxSections` 的 `keyword` 路径保持不搜正文（非搜索态列表不走它）。

Debug 无登录场景必须走同一套原生写入和检索：`writeLocalValue('session:…')` 也要重建旁路表，不能只挂在 `DataRuntime.writeSession` 上。

## 旁路表

仍在 `catalog.sqlite`，与 KV 同库，不另开文件。

```sql
CREATE TABLE IF NOT EXISTS session_prose (
  user_id TEXT NOT NULL,
  workspace_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  item_id TEXT NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY (user_id, workspace_id, session_id, entry_id, item_id)
);
CREATE INDEX IF NOT EXISTS session_prose_session
  ON session_prose (user_id, workspace_id, session_id);
```

重建时机：`LocalStore.write` / `writeSession` 只要 key 是 `session:` 前缀。解析 `session:` 后的 JSON 数组 `[userId, workspaceId, sessionId]`。先删该会话全部行，再从 envelope `entries` 插入非空散文。value 不是合法 envelope 则删行不插入（预览空态）。`clear()` 同时 `DELETE FROM session_prose`。

抽取函数单一来源，Inbox 写入和会话内 find 共用：只收集 `type == "text" || type == "thought"` 且 `text` 去空白后非空的项。换行归一成 `\n`，不做 markdown 去语法（原生 cell 按源文本绘制，偏移与源字符串对齐）。

单条 session 缓存仍受 12 MiB 写入上限。写失败则不更新旁路表，保留上一份。

## Inbox 检索

`LodyKit.searchInbox(userId, workspaceId, query) -> InboxSearchHits`

```ts
type InboxSearchHits = {
  projectIds: string[];
  sessions: { id: string; snippet: string | null }[];
};
```

在 `LocalStore.queue` 上跑，不在主线程解析 JSON。

1. `query.trim()` 为空则返回空 hits。RN 此时走非搜索列表。
2. 读 `catalog:${userId}:${workspaceId}`。形状是 `{ catalog, syncedAt }`；缺 catalog 则项目/标题命中为空，正文仍可命中旁路表。
3. 项目：非 chat 项目，`name` 或 `rootPath` 命中。
4. 会话：`title`、项目名或聊天分组名（`LodyStrings` 的 `inbox.section.chat`，与 `sessionPlace` 相同）、`branchName`、所属项目 `rootPath` 任一命中 → `snippet: null`（副标题保持 `sessionPlace`）。
5. 否则若该会话旁路表任一 `text` 命中 → `snippet` 为第一处摘录（命中前后约 40 字，优先在空白处截断，空白压缩成单空格）。
6. 会话顺序与现在相同：命中集按 catalog 的 `byActivity`（RN 排序，原生只返回 id）。原生返回的 session 数组可不排序，RN 用 catalog 顺序滤出。
7. 已归档会话：搜索态包含，与现在一致。

RN 用 generation 丢弃过期结果。`searchInbox` 失败：toast，并回退到仅 catalog 标题/项目名的 JS 匹配（现 `searchSections` 逻辑抽出 `matchCatalog`），列表不得空白。

`useInboxModel`（Inbox 与 iPad 侧栏）在 `query.trim()` 有值时调 `searchInbox`，再 `searchSections(catalog, hits, accent)`。

摘录是普通 `subtitle` 字符串。不高亮、不用 attributed。

## 会话内 find

UIKit 条挂在 `LodyChatView` 上，不使用 Inbox 的 `UISearchController`，不包进 RN 键盘避让。

条上：输入、`当前 / 总数`、上一条、下一条、关闭。44 pt 触控。系统强调色高亮（当前命中与其他命中有对比），不用绿色。

`LodyChatView` 方法：

- `openFind(query: String, keyboard: Bool)` — 打开条；`keyboard == true` 时成为 first responder。
- `closeFind()` — 关掉条，清高亮。

更多菜单「查找」调 `openFind("", true)`。

Inbox 点入：`SessionNavIntent.open` 与 `SessionParams` 增加可选 `findQuery?: string`（只在内存，不进 URL）。`useBindSessionNav` 打开时传入。`SessionScreen` 在 `NativeChat` 上屏且已有 `preparedEntries` / `entriesJSON` 后调一次 `openFind(findQuery, false)`。同一 `findQuery` 不因流式 revision 再调。用户按上/下一条才移动。

匹配当前已加载 `ChatTranscript` 的散文行，算法与旁路抽取相同，`localizedStandardContains`。工具行不进结果。空查询：无高亮，导航禁用。有查询无命中：计数区「无结果」，导航禁用。Return 下一条。关闭清高亮。

用户点「更早的记录」加载后，若 find 条仍开着，重跑匹配并更新计数；不自动继续翻页。有更早页未加载时，不把总数说成全会话。

流式追加：更新高亮范围，不抢滚动，除非当前活动命中的那一行被替换。

## 文案

| key                          | zh-Hans                                                    | en                                                                                                |
| ---------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `search.field.placeholder`   | 保持「搜索项目或会话」                                     | 保持现有                                                                                          |
| `search.placeholder.noMatch` | 没有匹配的项目或会话。也可以搜索这台设备打开过的会话内容。 | No matching projects or sessions. Content search only covers conversations opened on this device. |
| `search.placeholder.idle`    | 保持现有（已写「包括已归档」）                             | 保持现有                                                                                          |
| `session.action.find`        | 查找                                                       | Find                                                                                              |
| 原生 find 占位               | 查找对话                                                   | Find in conversation                                                                              |
| 原生无结果                   | 无结果                                                     | No results                                                                                        |
| 原生计数                     | `{current} / {total}`                                      | `{current} / {total}`                                                                             |

零命中才用 `search.placeholder.noMatch`。有任意项目或会话行时不出现这句。

find 条字符串走 `LodyStrings`（UIKit）。菜单项走 RN locale。

## 失败与边界

- 旁路表与 KV 会话缓存以写入时刻为准。桌面继续聊过、手机未再打开：Inbox 正文可能过期；打开会话后 find 以当前 replica 为准。
- 从未打开过的会话：只有标题/项目/路径/分支能命中。
- 打开过但 12 MiB 没写成：没有正文行。
- 账号/工作区隔离与现有 `session:` key 相同。
- 登出 `clear()` 后检索为空。
- 不把 Inbox 结果做成按消息多行。
- 不把整个列表搬进 Swift。

## 不做

- FTS5、Core Spotlight、`UIFindInteraction`
- 后台 bootstrap 全部会话历史
- 工作区全文（没打开过的会话）
- 列表 attributed 高亮
- 把 catalog / transcript 改成领域表
- 自动加载全部历史来凑 find 总数
- 搜索词进 URL / 深链

## 验证

不登录。Home Debug 已写入 `ui-design` 的 session 缓存（用户「设计首页」、助手「用项目分组。」、tool「读取」）。在此上扩：

Swift（`modules/lody-kit/verification`，与 `local-store` 同类）：

- 写入 envelope 后 `searchInbox` 能用「用项目分组」命中，`snippet` 含该句
- 搜 tool 标题「读取」不命中该会话
- 搜标题仍命中；标题命中时 `snippet == nil`
- 中文 `localizedStandardContains`（大小写英文字母）
- `clear()` 后正文不再命中
- 抽取：`text`/`thought` 进表，`tool_call`/`plan` 不进
- find 匹配：散文命中、tool 不命中、空查询无结果

UI（`verification/ui`，Home + Chat 预览，Inbox 与 iPad 侧栏都要跑到）：

- 标题/项目名照旧过滤
- 搜「用项目分组」出现该会话，副标题是摘录
- 搜「读取」不因 tool 标题出现
- 零命中看到内容搜索边界说明
- 点正文命中行：进会话、find 条带词、滚到第一条、键盘不弹
- 会话内更多 → 查找：焦点在输入框；上/下一条；关闭清高亮
- 只在已加载行计数

`pnpm check` 覆盖改过的 TS；Swift 检查跟现有 verification 一样可单独 `swiftc`。Simulator 构建走 `pnpm verify:build` / `pnpm verify:simulator`，不另开 DerivedData。

## 相关

- 上游：`packages/components/src/lib/session-chat-search.ts`（只索引散文）
- 本仓：`LocalStore.swift`、`inbox.ts` `searchSections`、`useInboxModel.ts`、`sessionNav.ts`、`SessionScreen.tsx`、`LodyChatView.swift`、`ChatTranscript.swift`
- 父 issue：#29 / #13 / #7
