import Foundation

let json = """
[{"id":"reply","role":"assistant","status":"running","finished":false,"items":[
{"itemId":"intro","type":"thought","text":"先检查"},
{"itemId":"tool","type":"tool_call","title":"读取文件","status":"completed"},
{"itemId":"answer","type":"text","text":"最终答案"}]}]
"""
var transcript = ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(json.utf8)))
let streaming = transcript.rows()
assert(!streaming.contains { $0.itemID == "tool" || $0.itemID == "intro" })
assert(streaming.contains { $0.kind == "summary" && $0.actionable })
let process = transcript.rows(processEntryID: "reply")
assert(process.map(\.itemID) == ["intro", "tool"])
assert(!process.contains { $0.kind == "summary" || $0.itemID == "answer" })
assert(transcript.rows(processEntryID: "other").isEmpty)
let finished = json.replacingOccurrences(of: "\"finished\":false", with: "\"finished\":true")
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(finished.utf8))
assert(transcript.rows().map(\.id) == streaming.map(\.id), "Completion must not insert or remove main-list rows")
assert(transcript.rows(processEntryID: "reply").map(\.id) == process.map(\.id), "The process sheet stays flat after completion")
let failure = finished.replacingOccurrences(of: "\"status\":\"completed\"", with: "\"status\":\"failed\"")
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(failure.utf8))
assert(transcript.rows().contains { $0.kind == "summary" && $0.attention })
assert(transcript.rows(processEntryID: "reply").contains { $0.itemID == "tool" && $0.attention })
let permission = finished.replacingOccurrences(of: "\"status\":\"completed\"", with: "\"permission\":{\"requestId\":\"p\",\"pending\":true}")
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(permission.utf8))
assert(transcript.rows().contains { $0.kind == "summary" && $0.attention })
assert(transcript.rows(processEntryID: "reply").contains { $0.itemID == "tool" && $0.actionable && $0.attention })
print("Chat: stable main rows, flat process sheet, errors and permissions passed")

let trailingTool = finished.replacingOccurrences(of: "\"text\":\"最终答案\"}", with: "\"text\":\"最终答案\"},{\"itemId\":\"tail\",\"type\":\"tool_call\"}")
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(trailingTool.utf8))
assert(transcript.rows().contains { $0.itemID == "answer" }, "A trailing status must not hide the answer")
assert(!transcript.rows().contains { $0.itemID == "tail" })

let proseBeforeTool = trailingTool.replacingOccurrences(of: "\"type\":\"thought\"", with: "\"type\":\"text\"")
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(proseBeforeTool.utf8))
assert(!transcript.rows().contains { $0.itemID == "intro" }, "Completed intermediate prose belongs to the process")
assert(transcript.rows(processEntryID: "reply").contains { $0.itemID == "intro" })

let multiStep = """
[{"id":"steps","role":"assistant","status":"running","finished":false,"items":[
{"itemId":"first","type":"text","text":"先检查"},
{"itemId":"think1","type":"thought","text":"分析路径"},
{"itemId":"read","type":"tool_call","title":"读取","status":"completed"},
{"itemId":"middle","type":"text","text":"继续验证"},
{"itemId":"think2","type":"thought","text":"分析结果"},
{"itemId":"write","type":"tool_call","title":"修改","status":"completed"},
{"itemId":"final","type":"text","text":"结论"}]}]
"""
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(multiStep.utf8))
assert(transcript.rows().map(\.kind) == ["text", "summary", "text", "summary", "text"])
assert(transcript.rows(processEntryID: "steps", processStartID: "think1").map(\.itemID) == ["think1", "read"])
assert(transcript.rows(processEntryID: "steps", processStartID: "think2").map(\.itemID) == ["think2", "write"])
transcript.entries[0].finished = true
assert(transcript.rows().map(\.kind) == ["summary", "text"])
assert(transcript.rows().last?.itemID == "final")
assert(transcript.rows(processEntryID: "steps").map(\.itemID) == ["first", "think1", "read", "middle", "think2", "write"])
assert(transcript.rows(processEntryID: "steps", processStartID: "think1").map(\.itemID) == ["think1", "read"], "An open segment must not change scope on completion")
print("Chat folding: live text boundaries, scoped process, and conclusion-only completion passed")

let completedWithNotice = """
[{"id":"done","role":"assistant","status":"pending","finished":true,
"fileDiffs":[{"path":"docs/.diff-check.md","add":1,"del":1}],
"items":[{"itemId":"tool","type":"tool_call","status":"completed"},{"itemId":"answer","type":"text","text":"done"}]},
{"id":"warning","role":"system","status":"pending","finished":false,
"items":[{"itemId":"notice","type":"system_notice","name":"agent_warning"}]}]
"""
let noticeEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(completedWithNotice.utf8))
let noticeTranscript = ChatTranscript(entries: noticeEntries)
assert(!noticeEntries.contains(where: \.isRunning), "A system notice is not an active assistant turn")
assert(noticeTranscript.rows().map(\.kind) == ["summary", "text", "changesHeader", "changes"])
assert(noticeTranscript.rows().last?.fileDiff?.path == "docs/.diff-check.md")
assert(noticeTranscript.rows().last?.fileDiff?.add == 1)
assert(noticeTranscript.rows().last?.group == "only")
assert(noticeTranscript.rows().contains { $0.kind == "changesHeader" && $0.text == "1 个文件" })
assert(noticeTranscript.rows(processEntryID: "warning").isEmpty)
assert(!noticeTranscript.rows(processEntryID: "done").contains { $0.kind == "changes" || $0.kind == "changesHeader" })
let cachedNotice = completedWithNotice.replacingOccurrences(of: ",\"name\":\"agent_warning\"", with: "")
let cachedEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(cachedNotice.utf8))
assert(ChatTranscript(entries: cachedEntries).rows() == noticeTranscript.rows())
var noticeStream = ChatStream()
noticeStream.receive(noticeEntries, animate: false)
noticeStream.receive(noticeEntries, animate: true)
assert(!noticeStream.hasPending)
print("Completed answer: file cards follow the answer; live and cached warnings never start processing")

let twoFiles = completedWithNotice.replacingOccurrences(
  of: "\"fileDiffs\":[{\"path\":\"docs/.diff-check.md\",\"add\":1,\"del\":1}]",
  with: "\"fileDiffs\":[{\"path\":\"src/a.ts\",\"add\":12,\"del\":4},{\"path\":\"src/b.ts\",\"add\":3,\"del\":1}]"
)
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(twoFiles.utf8))
let grouped = transcript.rows().filter { $0.kind == "changes" || $0.kind == "changesHeader" }
assert(grouped.map(\.kind) == ["changesHeader", "changes", "changes"])
assert(grouped[0].text == "2 个文件" && grouped[0].fileDiff?.add == 15 && grouped[0].fileDiff?.del == 5)
assert(grouped.dropFirst().map(\.group) == ["first", "last"])
print("File group: header totals and first/last membership passed")

var stream = ChatStream()
stream.receive([], animate: true)
let live = try JSONDecoder().decode([ChatEntry].self, from: Data(json.utf8))
stream.receive(live, animate: true)
assert(stream.hasPending)
assert(stream.presentation[0].items[2].text == "")
stream.advance()
assert(stream.presentation[0].items[2].text == "最")
let complete = try JSONDecoder().decode([ChatEntry].self, from: Data(finished.utf8))
stream.receive(complete, animate: true)
assert(!stream.presentation[0].finished, "Do not finish before the visible text drains")
for _ in 0..<30 { stream.advance() }
assert(!stream.hasPending && stream.presentation[0].finished)
assert(stream.presentation[0].items[2].text == "最终答案")
var historyStream = ChatStream()
historyStream.receive(live, animate: true)
assert(!historyStream.hasPending, "Opening history must not replay it")
let corrected = json.replacingOccurrences(of: "最终答案", with: "更正后的答案")
stream.receive(try JSONDecoder().decode([ChatEntry].self, from: Data(corrected.utf8)), animate: true)
assert(stream.presentation[0].items[2].text == "更正后的答案", "Replacement must not replay an obsolete suffix")
var unicodeStream = ChatStream()
unicodeStream.receive([], animate: true)
let unicode = json.replacingOccurrences(of: "最终答案", with: "👩🏽‍💻你好é")
unicodeStream.receive(try JSONDecoder().decode([ChatEntry].self, from: Data(unicode.utf8)), animate: true)
unicodeStream.advance()
assert(unicodeStream.presentation[0].items[2].text == "👩🏽‍💻")
unicodeStream.finish()
assert(!unicodeStream.hasPending && unicodeStream.presentation[0].items[2].text == "👩🏽‍💻你好é")
print("Chat stream: paced bursts, completion drain, history, replacement and Unicode passed")
var burstStream = ChatStream()
burstStream.receive([], animate: true)
let burst = json.replacingOccurrences(of: "最终答案", with: String(repeating: "文", count: 3000))
burstStream.receive(try JSONDecoder().decode([ChatEntry].self, from: Data(burst.utf8)), animate: true)
for _ in 0..<30 { burstStream.advance() }
assert(!burstStream.hasPending, "Large bursts must increase batch size instead of taking minutes")

var fade = ChatTextFade()
fade.update("已有文字", animate: false, at: 0, reset: true)
fade.update("已有文字👩🏽‍💻你好", animate: true, at: 1)
assert(fade.active.count == 3 && fade.active[0].range.location == 4)
assert(fade.active[0].range.length == "👩🏽‍💻".utf16.count)
assert(fade.active[0].opacity(at: 1) == 0 && fade.active[0].opacity(at: 1.11) > 0.49)
assert(fade.active[0].opacity(at: 1.3) == 1 && !fade.isAnimating(at: 1.3))
fade.update("已有文字👩🏽‍💻你好", animate: true, at: 2)
assert(!fade.isAnimating(at: 2), "Reconfiguration must not restart old characters")
fade.update("**hello", animate: false, at: 3, reset: true)
fade.update("hello", animate: true, at: 4)
assert(fade.active.isEmpty, "Closing Markdown must not fade the existing word again")
fade.update("hello world", animate: false, at: 5)
assert(fade.active.isEmpty, "Reduced motion inserts text immediately")
print("Character fade: graphemes, opacity, stable text, Markdown edits and reduced motion passed")
fade.update("aa", animate: false, at: 6, reset: true)
fade.update("aaa", animate: true, at: 7)
assert(fade.active.count == 1 && fade.active[0].range.location == 2)

assert(ChatScroll.bottom(contentHeight: 600, viewportHeight: 200, topInset: 100, bottomInset: 40) == 440)
assert(ChatScroll.bottom(contentHeight: 616, viewportHeight: 200, topInset: 100, bottomInset: 40) == 456,
  "Reflow must follow the actual bottom even without a new line")
assert(ChatScroll.bottom(contentHeight: 500, viewportHeight: 200, topInset: 100, bottomInset: 40) == 340,
  "Markdown contraction must not leave a stale target below the content")
assert(ChatScroll.bottom(contentHeight: 20, viewportHeight: 200, topInset: 100, bottomInset: 40) == -100,
  "Short content must respect the top inset")
print("Scroll bottom: growth, reflow, contraction and short content passed")

// Image history keeps media above the text bubble and reserves the user anchor.
let imageHistory = """
[{"id":"picture-turn","role":"user","status":"pending","finished":true,"items":[
{"itemId":"caption","type":"text","text":"What is this?"},
{"itemId":"photo","type":"image","image":{"id":"image1","fileName":"sample.png","width":800,"height":600}}
]}]
"""
var imageTranscript = ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(imageHistory.utf8)))
let pictureRows = imageTranscript.rows()
assert(pictureRows.map(\.kind) == ["image", "user"])
assert(pictureRows.first?.id == "picture-turn:user")
assert(pictureRows.first?.image?.id == "image1")
assert(pictureRows.last?.text == "What is this?", "Attachment filenames must not be flattened into the message bubble")
imageTranscript.entries[0].items.removeFirst()
assert(imageTranscript.rows().map(\.kind) == ["image"], "Image-only messages must not add an empty bubble")
print("Chat image rows: media before caption, stable anchor, and image-only layout passed")

let localPending = try! JSONDecoder().decode(ChatPendingSend.self, from: Data(#"{"id":"local-send","text":"hello","attachments":[{"id":"photo","name":"cat.png","uri":"file:///tmp/cat.png","kind":"image"}],"status":"正在上传…"}"#.utf8))
let pendingRows = localPending.rows(entries: [])
precondition(pendingRows.map(\.kind) == ["image", "user", "summary"], "A send must show its attachment, text and processing immediately")
precondition(pendingRows.first?.localImageURI == "file:///tmp/cat.png" && pendingRows.last?.running == true)
let authoritative = ChatEntry(id: "local-send", role: "user", status: "completed", finished: true, endedAt: nil, startedAt: nil, items: [], fileDiffs: nil)
precondition(localPending.rows(entries: [authoritative]).map(\.kind) == ["summary"], "Authoritative history must replace the pending user row without duplicating it")
var failedPending = localPending
failedPending.failed = true
precondition(failedPending.rows(entries: []).isEmpty, "A failed draft must leave the transcript for restoration")
print("Pending send: immediate text and attachment, processing, stable history takeover and failure passed")

var disconnectedPending = localPending
disconnectedPending.reconnect = true
let reconnectRows = disconnectedPending.rows(entries: [])
precondition(reconnectRows.count == pendingRows.count, "Reconnection must reuse the existing pending status row")
precondition(reconnectRows.last?.actionable == true && reconnectRows.last?.running == true, "Disconnected pending state must offer reconnect while retaining its animated status")
precondition(pendingRows.last?.actionable == false, "Ordinary pending status must not open the execution process")
print("Pending reconnect: one actionable status row while disconnected passed")
