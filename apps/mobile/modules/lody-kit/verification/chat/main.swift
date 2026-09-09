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
assert(streaming.contains { $0.kind == "summary" && $0.symbol == "circle.fill" },
  "Process rows must use a status pip, not a disclosure chevron")
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
let failedSummary = transcript.rows().first { $0.kind == "summary" }!
assert(!failedSummary.text.contains("native.chat.transcript.status.failed"), failedSummary.text)
assert(failedSummary.text.contains("native.chat.transcript.activity.thought"), failedSummary.text)
assert(failedSummary.text.contains("native.chat.transcript.activity.tools"), failedSummary.text)
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

let liveDurationJSON = """
[{"id":"timed-live","role":"assistant","status":"running","finished":false,
"timestamp":"1970-01-01T00:00:00.000Z",
"items":[{"itemId":"tool","type":"tool_call","status":"in_progress"}]}]
"""
let liveDurationEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(liveDurationJSON.utf8))
let liveDurationRows = ChatTranscript(entries: liveDurationEntries).rows(now: 65_999)
assert(liveDurationRows.map(\.kind) == ["duration", "summary"], "Duration must be the first assistant row")
assert(liveDurationRows[0].running && liveDurationRows[0].workDurationMs == 65_999,
  "A live turn must measure from timestamp to the injected clock")
assert(liveDurationRows[1].workDurationMs == nil,
  "The shiny process row must not own the static duration label")
assert(!liveDurationRows[0].shines && liveDurationRows[1].shines,
  "Only the process label may shine; the separate duration label must stay static")

let emptyReplyJSON = """
[{"id":"sent","role":"user","status":"completed","finished":true,
"startedAt":1000,
"items":[{"itemId":"prompt","type":"text","text":"hello"}]},
{"id":"empty-reply","role":"assistant","status":"running","finished":false,
"startedAt":3000,"items":[]}]
"""
let emptyReplyEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(emptyReplyJSON.utf8))
let emptyReplyRows = ChatTranscript(entries: emptyReplyEntries).rows(now: 3_500)
assert(emptyReplyRows.map(\.kind) == ["user", "duration"],
  "An empty authoritative assistant shell must already provide the uninterrupted status row")
assert(emptyReplyRows.last?.id == "sent:duration" && emptyReplyRows.last?.entryID == "empty-reply",
  "The server duration must retain the local turn's stable row identity")
assert(emptyReplyRows.last?.workDurationMs == 2_500,
  "Authoritative takeover must continue from the user submission instead of resetting at assistant start")
let locallyTimedReplyRows = ChatTranscript(entries: emptyReplyEntries).rows(
  now: 3_500,
  turnStartedAt: ["sent": 500]
)
assert(locallyTimedReplyRows.last?.workDurationMs == 3_000,
  "The locally published submission clock must survive authoritative takeover")

let finishedDurationJSON = """
[{"id":"timed-finished","role":"assistant","status":"completed","finished":true,
"timestamp":"1970-01-01T00:00:00.000Z","endedAt":125000,
"items":[{"itemId":"tool","type":"tool_call","status":"completed"},
{"itemId":"answer","type":"text","text":"done"}]}]
"""
let finishedDurationEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(finishedDurationJSON.utf8))
let finishedDurationRows = ChatTranscript(entries: finishedDurationEntries).rows(now: 999_999)
assert(finishedDurationRows.map(\.kind) == ["duration", "summary", "text"],
  "Completed duration must remain a separate first row")
let finishedDurationRow = finishedDurationRows.first
assert(finishedDurationRow?.workDurationMs == 125_000, "A finished turn must freeze at endedAt")
assert(
  ChatWorkDuration.format(3_665_999, hour: "h", minute: "m", second: "s") == "1h 01m 05s",
  "Duration formatting must match the OSS compact format"
)
assert(ChatWorkDuration.format(65_999, hour: "h", minute: "m", second: "s") == "1m 05s")
assert(ChatWorkDuration.format(999, hour: "h", minute: "m", second: "s") == "0s")

let fallbackDurationJSON = """
[{"id":"timed-fallback","role":"assistant","status":"running","finished":false,
"startedAt":1000,
"items":[{"itemId":"tool","type":"tool_call","status":"in_progress"}]}]
"""
let fallbackDurationEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(fallbackDurationJSON.utf8))
assert(
  ChatTranscript(entries: fallbackDurationEntries).rows(now: 3_500).first?.workDurationMs == 2_500,
  "Legacy startedAt must remain a fallback when timestamp is absent"
)

let invalidDurationJSON = finishedDurationJSON.replacingOccurrences(of: "\"endedAt\":125000", with: "\"endedAt\":-1")
let invalidDurationEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(invalidDurationJSON.utf8))
assert(
  !ChatTranscript(entries: invalidDurationEntries).rows(now: 999_999).contains { $0.kind == "duration" },
  "An end before the turn start must not show a duration"
)
print("Chat duration: live clock, frozen completion, legacy fallback, invalid range and compact formatting passed")

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
// A CLI harness has no compiled catalog, so plural rows fall back to the key;
// the strings check covers the Foundation substitution itself.
assert(noticeTranscript.rows().contains { $0.kind == "changesHeader" && $0.text == "native.chat.transcript.fileCount" })
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
assert(grouped[0].text == "native.chat.transcript.fileCount" && grouped[0].fileDiff?.add == 15 && grouped[0].fileDiff?.del == 5)
assert(grouped.dropFirst().map(\.group) == ["first", "last"])
print("File group: header totals and first/last membership passed")

let mixedFail = """
[{"id":"mixed","role":"assistant","status":"completed","finished":true,"items":[
{"itemId":"think","type":"thought","text":"先检查"},
{"itemId":"read1","type":"tool_call","kind":"read","path":"a.ts","status":"completed"},
{"itemId":"read2","type":"tool_call","kind":"read","path":"a.ts","status":"failed"},
{"itemId":"edit","type":"tool_call","kind":"edit","path":"b.ts","status":"completed"},
{"itemId":"run","type":"tool_call","kind":"execute","status":"completed"},
{"itemId":"answer","type":"text","text":"结论"}]}]
"""
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(mixedFail.utf8))
let mixedSummary = transcript.rows().first { $0.kind == "summary" }!
assert(mixedSummary.attention)
assert(!mixedSummary.text.contains("native.chat.transcript.status.failed"), mixedSummary.text)
assert(!mixedSummary.text.contains("native.chat.transcript.status.done"), mixedSummary.text)
assert(mixedSummary.text.contains("native.chat.transcript.activity.thought"), mixedSummary.text)
assert(mixedSummary.text.contains("native.chat.transcript.activity.readFiles"), mixedSummary.text)
assert(mixedSummary.text.contains("native.chat.transcript.activity.editedFiles"), mixedSummary.text)
assert(mixedSummary.text.contains("native.chat.transcript.activity.commands"), mixedSummary.text)
let liveThink = """
[{"id":"live","role":"assistant","status":"running","finished":false,"items":[
{"itemId":"think","type":"thought","text":"分析"},
{"itemId":"read","type":"tool_call","kind":"read","status":"in_progress"}]}]
"""
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(liveThink.utf8))
let liveSummary = transcript.rows().first { $0.kind == "summary" }!
assert(liveSummary.text.contains("native.chat.transcript.activity.thinking"), liveSummary.text)
assert(!liveSummary.text.contains("native.chat.transcript.status.running"), liveSummary.text)
let previewCache = "{\"v\":1,\"status\":\"live\",\"revision\":1,\"entries\":" + mixedFail + "}"
let previewRows = ChatTranscript.previewRows(from: previewCache)
let previewKinds = Set(previewRows.map(\.kind))
assert(previewKinds.contains("summary"))
assert(previewKinds.contains("text"))
assert(previewRows.contains { $0.kind == "summary" && $0.attention })
assert(ChatTranscript.previewRows(from: "{}").isEmpty)
print("Process summary enumerates activity and keeps partial failures off the title")

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

var fastStream = ChatStream()
fastStream.receive([], animate: true)
for chunk in 1...240 {
  var input = live
  let source = String(repeating: "word", count: chunk * 15)
  input[0].items[2].text = source
  fastStream.receive(input, animate: true)
  fastStream.advance()
  precondition(fastStream.presentation[0].items[2].text == source,
    "300 synthetic TPS must not accumulate an artificial character queue")
}
var longTail = live
longTail[0].items[2].text = String(repeating: "word", count: 3600) + "👩🏽‍💻"
fastStream.receive(longTail, animate: true)
fastStream.advance()
precondition(!fastStream.hasPending && fastStream.presentation[0].items[2].text == longTail[0].items[2].text,
  "A long block must commit even a small final suffix without another character queue")
precondition(ChatScroll.advance(100, toward: 101, elapsed: 1.0 / 60, response: 0.1, minimumStep: 1.0 / 3) == 101,
  "The bottom follower must finish when UIKit would round its next step away")
print("Streaming pressure: sustained 300 TPS, long tail drain, and pixel-aligned scroll completion passed")

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

// A moving tail must traverse intermediate positions, never overshoot, and
// converge to the same place on different refresh-rate displays.
func follow(_ rate: Int) -> Double {
  var y = 0.0
  for frame in 0..<rate {
    let target = frame < rate / 2 ? 600.0 : 1000.0
    let next = ChatScroll.advance(y, toward: target, elapsed: 1.0 / Double(rate), response: 0.10)
    precondition(next > y && next < target)
    y = next
  }
  return y
}
precondition(abs(follow(60) - follow(120)) < 0.001)
precondition(ChatScroll.advance(100, toward: 100.2, elapsed: 1.0 / 60, response: 0.10) == 100.2)
let shrink = ChatScroll.advance(100, toward: 20, elapsed: 1.0 / 60, response: 0.06)
precondition(shrink > 20 && shrink < 100)
precondition(ChatScroll.advance(100, toward: 20, elapsed: 0, response: 0.06) == 100)
print("Chat motion: continuous retargeting, contraction, convergence, and refresh-rate independence passed")

let pendingStartedAt = Date().timeIntervalSince1970 * 1000 - 2_500
let localPendingJSON = """
{"id":"local-send","text":"hello","attachments":[
{"id":"photo","name":"cat.png","uri":"file:///tmp/cat.png","kind":"image"}],
"status":"正在上传…","startedAt":\(pendingStartedAt)}
"""
let localPending = try! JSONDecoder().decode(ChatPendingSend.self, from: Data(localPendingJSON.utf8))
let pendingRows = localPending.rows(entries: [])
precondition(pendingRows.map(\.kind) == ["image", "user", "duration"],
  "A send must show its attachment, text and a separate static duration immediately")
precondition(pendingRows.first?.localImageURI == "file:///tmp/cat.png" && pendingRows.last?.running == true)
precondition(pendingRows.last?.id == "local-send:duration")
precondition((2_400...3_000).contains(pendingRows.last?.workDurationMs ?? -1),
  "The local duration must start at submission time")
precondition(ChatWorkDuration.needsTimer(pendingRows),
  "A local duration row must keep advancing before the server replies")
precondition(ChatWorkDuration.needsTimer(liveDurationRows))
precondition(!ChatWorkDuration.needsTimer(finishedDurationRows))
let authoritative = ChatEntry(id: "local-send", role: "user", status: "completed", finished: true, timestamp: nil, endedAt: nil, startedAt: nil, items: [], fileDiffs: nil)
precondition(localPending.rows(entries: [authoritative]).map(\.kind) == ["duration"],
  "Authoritative user history must replace the pending user row without interrupting duration")
var failedPending = localPending
failedPending.failed = true
precondition(failedPending.rows(entries: []).isEmpty, "A failed draft must leave the transcript for restoration")
print("Pending send: immediate text and attachment, processing, stable history takeover and failure passed")

var disconnectedPending = localPending
disconnectedPending.reconnect = true
let reconnectRows = disconnectedPending.rows(entries: [])
precondition(reconnectRows.count == pendingRows.count, "Reconnection must reuse the existing pending status row")
precondition(reconnectRows.last?.actionable == true && reconnectRows.last?.running == true,
  "Disconnected pending state must offer reconnect through the same static duration row")
precondition(pendingRows.last?.actionable == false, "Ordinary pending status must not open the execution process")
print("Pending reconnect: one actionable status row while disconnected passed")

func notifyTurn(_ previous: String?, _ next: String?, process: String = "", window: Bool = true) -> Bool {
  ChatHaptics.shouldNotifyTurnCompletion(
    previousLive: previous,
    nextLive: next,
    processEntryID: process,
    inWindow: window
  )
}
precondition(!notifyTurn(nil, nil), "Opening completed history must not buzz")
precondition(!notifyTurn(nil, "a"), "Starting a live turn must not buzz")
precondition(!notifyTurn("a", "a"), "Streaming the same live turn must not buzz")
precondition(notifyTurn("a", nil), "A finished live turn must buzz")
precondition(notifyTurn("a", "b"), "A queued next turn must still buzz for the finished round")
precondition(!notifyTurn("a", nil, process: "a"), "The process sheet must not duplicate the session haptic")
precondition(!notifyTurn("a", nil, window: false), "Detached chat must not buzz")
print("Chat haptics: completion fires once per finished round")

var queueTranscript = ChatTranscript()
queueTranscript.entries = try! JSONDecoder().decode([ChatEntry].self, from: Data(#"[{"id":"queued-turn","role":"user","status":"queued","finished":false,"items":[{"itemId":"text","type":"text","text":"Wait for me"}]}]"#.utf8))
precondition(queueTranscript.rows().isEmpty, "Queued input must never render in the transcript")
let queuedPending = try! JSONDecoder().decode(ChatPendingSend.self, from: Data(#"{"id":"queued-turn","text":"Wait for me","attachments":[],"status":"Sending","queue":true}"#.utf8))
precondition(queuedPending.rows(entries: []).isEmpty, "Optimistic queued input must never flash as a sent message")
queueTranscript.entries = try! JSONDecoder().decode([ChatEntry].self, from: Data(#"[{"id":"queued-turn","role":"user","status":"processing","finished":true,"items":[{"itemId":"text","type":"text","text":"Wait for me"}]}]"#.utf8))
precondition(queueTranscript.rows().filter { $0.kind == "user" }.count == 1, "Consumed queue input must appear exactly once using its original identity")
print("Queue transcript: hidden while queued or pending; one message on execution passed")
