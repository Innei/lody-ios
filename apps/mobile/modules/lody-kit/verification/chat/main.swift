import ChatKitCore
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
assert(!streaming.contains { $0.kind == "meta" }, "A live reply must not offer completed-message actions")
assert(transcript.rows().filter { $0.kind != "meta" }.map(\.id) == streaming.map(\.id), "Completion preserves existing main-list rows")
assert(transcript.rows().contains { $0.kind == "meta" && $0.text.isEmpty }, "Old replies retain actions without inventing metadata")
assert(transcript.rows(processEntryID: "reply").map(\.id) == process.map(\.id), "The process sheet stays flat after completion")
let failure = finished.replacingOccurrences(of: "\"status\":\"completed\"", with: "\"status\":\"failed\"")
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(failure.utf8))
assert(transcript.rows().contains { $0.kind == "summary" && $0.attention })
assert(transcript.rows(processEntryID: "reply").contains { $0.itemID == "tool" && $0.attention })
let failedSummary = transcript.rows().first { $0.kind == "summary" }!
assert(!failedSummary.text.contains("native.chat.transcript.status.failed"), failedSummary.text)
assert(failedSummary.text.contains("native.chat.transcript.activity.thought"), failedSummary.text)
assert(failedSummary.text.contains("native.chat.transcript.activity.tools"), failedSummary.text)
assert(failedSummary.symbol == "exclamationmark.triangle.fill",
  "A failed tool in the process must replace the status pip with a warning mark")
assert(!failedSummary.shines, "A finished process must not shine")

let liveFailedJSON = """
[{"id":"live-fail","role":"assistant","status":"running","finished":false,"items":[
{"itemId":"intro","type":"thought","text":"先检查"},
{"itemId":"tool","type":"tool_call","title":"读取文件","status":"failed"}]}]
"""
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(liveFailedJSON.utf8))
let liveFailed = transcript.rows().first { $0.kind == "summary" }!
assert(liveFailed.attention)
assert(liveFailed.running)
assert(liveFailed.shines, "A live process with a failed tool must keep the shine")
assert(liveFailed.symbol == "exclamationmark.triangle.fill",
  "A live process with a failed tool must show a warning mark instead of the pip")
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
assert(transcript.rows().map(\.kind) == ["summary", "text", "meta"])
assert(transcript.rows().last(where: { $0.kind == "text" })?.itemID == "final")
transcript.entries[0].modelInfo = ChatEntry.ModelInfo(modelId: "actual", name: "Actual Model", thoughtLevel: "High")
assert(transcript.rows().last?.text == "Actual Model · High")
assert(transcript.rows().last?.imageAsset == "", "Unknown models must not invent a provider mark")
assert(LodyAgentIcon.asset(modelId: "gpt-5.6-sol", name: "GPT-5.6 Sol") == "lody-agent-openai")
assert(LodyAgentIcon.asset(modelId: "claude-opus-4", name: "Opus 4") == "lody-agent-claude")
assert(LodyAgentIcon.asset(modelId: "grok-4.6", name: nil) == "lody-agent-grok")
assert(LodyAgentIcon.asset(modelId: "kimi-code", name: nil) == "lody-agent-kimi")
assert(LodyAgentIcon.asset(modelId: "gemini-2.5-pro", name: "Gemini 2.5 Pro") == "lody-agent-gemini")
assert(LodyAgentIcon.asset(modelId: "actual", name: "Actual Model") == nil)
let modelOnlyJSON = """
[{"id":"no-text","role":"assistant","status":"completed","finished":true,
"modelInfo":{"modelId":"id-only"},"items":[]}]
"""
let modelOnlyRows = ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(modelOnlyJSON.utf8))).rows()
assert(modelOnlyRows.last?.text == "id-only", "Model-only replies still show metadata")
assert(modelOnlyRows.last?.imageAsset == "", "An unmatched model id stays text-only")
let openaiMetaJSON = """
[{"id":"openai-meta","role":"assistant","status":"completed","finished":true,
"modelInfo":{"modelId":"gpt-5.6-sol","name":"GPT-5.6 Sol","thoughtLevel":"High"},"items":[]}]
"""
let openaiMetaRows = ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(openaiMetaJSON.utf8))).rows()
assert(openaiMetaRows.last?.kind == "meta")
assert(openaiMetaRows.last?.text == "GPT-5.6 Sol · High")
assert(openaiMetaRows.last?.imageAsset == "lody-agent-openai", "Known providers put their mark on the model line")
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
assert(liveDurationRows[0].actionable == false, "A live timer must not reserve a reconnect control")
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
assert(finishedDurationRows.map(\.kind) == ["duration", "text", "meta"],
  "Completed work absorbs the folded process instead of stacking a second chrome row")
let finishedDurationRow = finishedDurationRows.first
assert(finishedDurationRow?.workDurationMs == 125_000, "A finished turn must freeze at endedAt")
assert(finishedDurationRow?.actionable == true, "The merged work row must open the process")
let timedThoughtJSON = finishedDurationJSON.replacingOccurrences(
  of: "\"type\":\"tool_call\",\"status\":\"completed\"",
  with: "\"type\":\"thought\",\"text\":\"Analyze\""
)
let timedThoughtTranscript = ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(timedThoughtJSON.utf8)))
let timedThoughtRow = timedThoughtTranscript.rows().first!
assert(timedThoughtRow.kind == "duration" && timedThoughtRow.workDurationMs == 125_000)
assert(timedThoughtRow.text == LodyStrings.text("native.chat.transcript.status.workedFor", ["duration": ChatWorkDuration.format(
  125_000, hour: LodyStrings.text("native.chat.duration.hour"),
  minute: LodyStrings.text("native.chat.duration.minute"), second: LodyStrings.text("native.chat.duration.second")
)]), "Completed thought-only work shows elapsed time without a redundant thought label or separator")
assert(timedThoughtRow.actionable && timedThoughtTranscript.rows(processEntryID: "timed-finished").first?.text == "Analyze",
  "The duration must still open the original thought content")
assert(
  finishedDurationRow?.text.contains("native.chat.transcript.activity.tools") == true
    || finishedDurationRow?.text.contains(" · ") == true,
  "The folded process title must follow the work duration"
)
assert(
  ChatWorkDuration.format(3_665_999, hour: "h", minute: "m", second: "s") == "1h 01m 05s",
  "Duration formatting must match the OSS compact format"
)
assert(ChatWorkDuration.format(65_999, hour: "h", minute: "m", second: "s") == "1m 05s")
assert(ChatWorkDuration.format(999, hour: "h", minute: "m", second: "s") == "0s")

let waitedDurationJSON = finishedDurationJSON.replacingOccurrences(
  of: "\"endedAt\":125000", with: "\"endedAt\":125000,\"permissionWaitMs\":5000"
)
let waitedDurationEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(waitedDurationJSON.utf8))
assert(
  ChatTranscript(entries: waitedDurationEntries).rows(now: 999_999).first?.workDurationMs == 120_000,
  "Finished work must subtract permissionWaitMs"
)
let liveWaitedJSON = liveDurationJSON.replacingOccurrences(
  of: "\"timestamp\":\"1970-01-01T00:00:00.000Z\"",
  with: "\"timestamp\":\"1970-01-01T00:00:00.000Z\",\"permissionWaitMs\":5000"
)
let liveWaitedEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(liveWaitedJSON.utf8))
assert(
  ChatTranscript(entries: liveWaitedEntries).rows(now: 65_999).first?.workDurationMs == 60_999,
  "A live timer must subtract permission wait already written on the replica"
)
let overWaitJSON = finishedDurationJSON.replacingOccurrences(
  of: "\"endedAt\":125000", with: "\"endedAt\":125000,\"permissionWaitMs\":200000"
)
let overWaitEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(overWaitJSON.utf8))
assert(
  ChatTranscript(entries: overWaitEntries).rows(now: 999_999).first?.workDurationMs == 0,
  "Wait longer than the span must clamp to zero"
)
let invalidWaitJSON = finishedDurationJSON.replacingOccurrences(
  of: "\"endedAt\":125000", with: "\"endedAt\":125000,\"permissionWaitMs\":-1"
)
let invalidWaitEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(invalidWaitJSON.utf8))
assert(
  ChatTranscript(entries: invalidWaitEntries).rows(now: 999_999).first?.workDurationMs == 125_000,
  "Illegal permissionWaitMs must be treated as zero"
)

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
let metaNow = utc.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12))!
  .timeIntervalSince1970 * 1000
let metaDay = 86_400_000.0
assert(ChatMetaTime.label(nil, now: metaNow) == "", "A reply without an end time shows no timestamp")
assert(ChatMetaTime.label(-1, now: metaNow) == "")
let sameDayLabel = ChatMetaTime.label(metaNow - 3_600_000, now: metaNow, calendar: utc)
let recentLabel = ChatMetaTime.label(metaNow - 3 * metaDay, now: metaNow, calendar: utc)
let oldLabel = ChatMetaTime.label(
  metaNow - Double(ChatMetaTime.relativeDayLimit) * metaDay, now: metaNow, calendar: utc
)
assert(sameDayLabel.contains(":") && !sameDayLabel.contains("2026"),
  "Same-day replies show a clock time, not a date")
assert(!recentLabel.contains("2026") && recentLabel != sameDayLabel,
  "Replies inside the relative window read as a day count")
assert(oldLabel.contains("2026") && !oldLabel.contains(":"),
  "Beyond the relative window the timestamp falls back to a calendar date")
let sameDayMetaJSON = finishedDurationJSON.replacingOccurrences(
  of: "\"endedAt\":125000", with: "\"endedAt\":\(Int(metaNow))"
)
let sameDayMetaEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(sameDayMetaJSON.utf8))
let sameDayMetaRow = ChatTranscript(entries: sameDayMetaEntries).rows(now: metaNow).last
assert(sameDayMetaRow?.kind == "meta" && sameDayMetaRow?.text.contains(":") == true,
  "The metadata bar carries the finish time even without model info")

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
assert(noticeTranscript.rows().map(\.kind) == ["summary", "text", "meta", "changesHeader", "changes"])
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
assert(mixedSummary.symbol == "exclamationmark.triangle.fill")
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
// Earlier process groups keep the turn's live label while only the latest group animates.
transcript.entries[0].items.append(try JSONDecoder().decode(ChatItem.self, from: Data(
  #"{"itemId":"progress","type":"text","text":"Still working"}"#.utf8
)))
transcript.entries[0].items.append(try JSONDecoder().decode(ChatItem.self, from: Data(
  #"{"itemId":"next-thought","type":"thought","text":"Next step"}"#.utf8
)))
let liveGroups = transcript.rows().filter { $0.kind == "summary" }
assert(liveGroups.count == 2)
assert(liveGroups.allSatisfy { $0.text.contains("native.chat.transcript.activity.thinking") })
assert(!liveGroups[0].running && liveGroups[1].running)
transcript.entries[0].finished = true
let finishedGroup = transcript.rows().first { $0.kind == "summary" }!
assert(!finishedGroup.running)
assert(!finishedGroup.text.contains("native.chat.transcript.activity.thinking"))
let previewCache = "{\"v\":1,\"status\":\"live\",\"revision\":1,\"entries\":" + mixedFail + "}"
let previewRows = ChatTranscript.previewRows(from: previewCache)
let previewKinds = Set(previewRows.map(\.kind))
assert(previewKinds.contains("summary"))
assert(previewKinds.contains("text"))
assert(!previewKinds.contains("meta"), "Read-only context-menu peeks omit message actions")
assert(previewRows.contains { $0.kind == "summary" && $0.attention })
assert(ChatTranscript.previewRows(from: "{}").isEmpty)
assert(
  ChatTranscriptPreviewMetrics.itemWidth(collectionWidth: 0) == 288,
  "A context-menu preview must not measure rows against a zero collection"
)
assert(
  ChatTranscriptPreviewMetrics.itemWidth(collectionWidth: 1) == 288,
  "A 1 pt collection is still an unset preview, not a column"
)
assert(
  ChatTranscriptPreviewMetrics.itemWidth(collectionWidth: 320) == 288,
  "A settled 320 pt preview keeps the section insets"
)
print("Process summary enumerates activity and keeps partial failures off the title")

var stream = ChatStream()
stream.receive([], animate: true)
let live = try JSONDecoder().decode([ChatEntry].self, from: Data(json.utf8))
stream.receive(live, animate: true, at: 0)
assert(stream.hasPending)
assert(stream.presentation[0].items[2].text == "")
stream.advance(at: 0.048)
assert(!stream.presentation[0].items[2].text!.isEmpty && "最终答案".hasPrefix(stream.presentation[0].items[2].text!) && stream.hasPending)
let complete = try JSONDecoder().decode([ChatEntry].self, from: Data(finished.utf8))
stream.receive(complete, animate: true, at: 0.05)
assert(!stream.presentation[0].finished, "Do not finish before the visible text drains")
assert(!ChatTranscript(entries: stream.presentation).rows().contains { $0.kind == "meta" })
for tick in 2...30 { stream.advance(at: Double(tick) * 0.048) }
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
unicodeStream.receive(try JSONDecoder().decode([ChatEntry].self, from: Data(unicode.utf8)), animate: true, at: 0)
unicodeStream.advance(at: 0.024)
assert(unicodeStream.presentation[0].items[2].text == "👩🏽‍💻")
unicodeStream.finish()
assert(!unicodeStream.hasPending && unicodeStream.presentation[0].items[2].text == "👩🏽‍💻你好é")
print("Chat stream: paced bursts, completion drain, history, replacement and Unicode passed")
// Leaving the viewport drains presentation pacing without losing input or completion.
var offscreenStream = ChatStream()
offscreenStream.receive([], animate: true)
offscreenStream.receive(live, animate: true, at: 0)
let offscreenID = live[0].id
offscreenStream.finish(entries: [offscreenID])
assert(!offscreenStream.hasPending)
offscreenStream.receive(complete, animate: true, deferredEntries: [offscreenID], at: 1)
assert(!offscreenStream.hasPending && offscreenStream.presentation[0].finished)
assert(offscreenStream.presentation[0].items[2].text == "最终答案")
offscreenStream.receive(try JSONDecoder().decode([ChatEntry].self, from: Data(corrected.utf8)),
  animate: true, deferredEntries: [offscreenID], at: 2)
assert(offscreenStream.presentation[0].items[2].text == "更正后的答案")
offscreenStream.receive([], animate: true, at: 3)
assert(offscreenStream.presentation.isEmpty && !offscreenStream.hasPending)
let frozenText = ChatRow(id: "reply:text", entryID: "reply", kind: "text", text: "Visible prefix", streaming: true)
let latestText = ChatRow(id: "reply:text", entryID: "reply", kind: "text", text: "Visible prefix and offscreen tail")
let offscreenPermission = ChatRow(id: "reply:permission", entryID: "reply", kind: "tool_call", text: "Permission required", actionable: true)
let frozenProjection = ChatStream.deferringMarkdown([latestText, offscreenPermission], previous: [frozenText])
assert(frozenProjection == [frozenText, offscreenPermission], "Offscreen Markdown must not hide newly actionable rows")
assert(ChatStream.deferringMarkdown([latestText], previous: frozenProjection) == [frozenText], "Dismissed actions must not stay in frozen rows")
print("Offscreen stream: full input, correction, completion and removal without reveal backlog passed")

var burstStream = ChatStream()
burstStream.receive([], animate: true)
let burst = json.replacingOccurrences(of: "最终答案", with: String(repeating: "文", count: 3000))
burstStream.receive(try JSONDecoder().decode([ChatEntry].self, from: Data(burst.utf8)), animate: true, at: 0)
for tick in 1...30 { burstStream.advance(at: Double(tick) * 0.048) }
assert(!burstStream.hasPending, "Large bursts must increase batch size instead of taking minutes")

var fastStream = ChatStream()
fastStream.receive([], animate: true)
for chunk in 1...240 {
  var input = live
  let source = String(repeating: "word", count: chunk * 15)
  input[0].items[2].text = source
  let time = Double(chunk) * 0.05
  fastStream.receive(input, animate: true, at: time)
  fastStream.advance(at: time + 0.048)
  let lag = source.count - fastStream.presentation[0].items[2].text!.count
  precondition(lag <= 180, "300 synthetic TPS must keep bounded latency, not an ever-growing queue")
}
var longTail = live
longTail[0].items[2].text = String(repeating: "word", count: 3600) + "👩🏽‍💻"
fastStream.receive(longTail, animate: true, at: 12.05)
fastStream.advance(at: 12.55)
precondition(!fastStream.hasPending && fastStream.presentation[0].items[2].text == longTail[0].items[2].text,
  "A long block must drain its last suffix promptly")

// Long and short replies use the same cadence; completion waits for the renderer.
for prefix in ["", String(repeating: "existing ", count: 1500)] {
  var paced = ChatStream()
  var input = live
  input[0].items[2].text = prefix
  paced.receive(input, animate: true, at: 0)
  input[0].items[2].text = prefix + String(repeating: "新", count: 48)
  paced.receive(input, animate: true, at: 0.1)
  paced.advance(at: 0.148)
  let shown = paced.presentation[0].items[2].text!.count - prefix.count
  assert(shown > 0 && shown < 48, "A 48-character burst must spread across commits at every message length")
  input[0].finished = true
  paced.receive(input, animate: true, at: 0.2)
  paced.advance(at: 0.56)
  assert(!paced.presentation[0].finished, "Final text must reach the renderer before completion")
  paced.advance(at: 0.6, animatingEntries: [input[0].id])
  assert(paced.hasPending && !paced.presentation[0].finished, "Do not fold while the final glyphs fade")
  paced.advance(at: 0.9)
  assert(!paced.hasPending && paced.presentation[0].finished)
}
precondition(ChatScroll.advance(100, toward: 101, elapsed: 1.0 / 60, response: 0.1, minimumStep: 1.0 / 3) == 101,
  "The bottom follower must finish when UIKit would round its next step away")
print("Streaming pressure: sustained 300 TPS, long tail drain, and pixel-aligned scroll completion passed")

var fade = CKTextFade()
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

let longPrefix = String(repeating: "stable ", count: 2000)
fade.update(longPrefix + "\n", animate: false, at: 8)
fade.update(longPrefix + "👩🏽‍💻new\n", animate: true, at: 8.096)
assert(fade.active.count == 4 && fade.active.first?.range.location == longPrefix.utf16.count)
let originalBirth = fade.active[0].start
fade.update(longPrefix + "👩🏽‍💻new!\n", animate: true, at: 8.15)
assert(fade.active[0].start == originalBirth, "Appending must preserve in-flight fades")
fade.update("hello **world", animate: false, at: 9)
fade.update("hello **world!", animate: true, at: 9.1)
let punctuationBirth = fade.active[0].start
fade.update("hello world!", animate: true, at: 9.15)
assert(fade.active.count == 1 && fade.active[0].range.location == 11 && fade.active[0].start == punctuationBirth,
  "Markdown closure moves the active suffix without replaying old words")
fade.update("", animate: false, at: 10)
fade.update(String(repeating: "👩🏽‍💻", count: 3000), animate: true, at: 10.096)
assert(fade.active.count <= 128 && NSMaxRange(fade.active.last!.range) == 3000 * "👩🏽‍💻".utf16.count)
assert(!fade.isAnimating(at: 10.4), "A large append must not leave seconds of invisible text")
fade.update("done", animate: false, at: 10.5)
assert(fade.active.isEmpty)
print("Long-text fades: bounded active ranges, Unicode, syntax closure, preserved births and visual completion passed")

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
assert(pictureRows.map(\.kind) == ["attachments", "user"])
assert(pictureRows.first?.id == "picture-turn:user")
assert(pictureRows.first?.attachments.first?.image?.id == "image1")
assert(pictureRows.last?.text == "What is this?", "Attachment filenames must not be flattened into the message bubble")
imageTranscript.entries[0].items.removeFirst()
assert(imageTranscript.rows().map(\.kind) == ["attachments"], "Image-only messages must not add an empty bubble")
print("Chat image rows: media before caption, stable anchor, and image-only layout passed")

let assistantImages = """
[{"id":"upload","role":"assistant","status":"running","finished":false,"items":[
{"itemId":"tool","type":"tool_call","title":"Upload images","status":"completed"},
{"itemId":"photos","type":"image_group","images":[{"id":"one","fileName":"one.png","storageSessionId":"source","width":600,"height":400},{"id":"two","fileName":"two.png"}]},
{"itemId":"answer","type":"text","text":"Uploaded"},
{"itemId":"last","type":"image","image":{"id":"three","fileName":"three.png"}}
]}]
"""
var uploadedTranscript = ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(assistantImages.utf8)))
let liveImageRows = uploadedTranscript.rows().filter { $0.image != nil }
precondition(liveImageRows.compactMap { $0.image?.id } == ["one", "two", "three"])
precondition(liveImageRows.first?.image?.storageSessionId == "source")
uploadedTranscript.entries[0].finished = true
precondition(uploadedTranscript.rows().filter { $0.image != nil } == liveImageRows,
  "Completion must preserve every uploaded image and its row identity")
precondition(uploadedTranscript.rows().map(\.kind) == ["summary", "image", "image", "text", "image", "meta"])
precondition(uploadedTranscript.rows(processEntryID: "upload").map(\.kind) == ["tool_call"],
  "Uploaded images belong in the conversation, not the collapsed process")
precondition(ChatTranscript.previewRows(from: assistantImages).filter { $0.image != nil } == liveImageRows)
uploadedTranscript.entries[0].items.removeAll { !$0.isImage }
precondition(uploadedTranscript.rows().map(\.kind) == ["image", "image", "image", "meta"],
  "Standalone MCP uploads must render without a tool or final text")
print("MCP images: multiple images, completion, standalone upload and cache restore passed")

let assistantFiles = """
[{"id":"files","role":"assistant","status":"running","finished":false,"items":[
{"itemId":"tool","type":"tool_call","title":"Upload files","status":"completed"},
{"itemId":"video","type":"file","file":{"id":"video","fileName":"clip.mp4","storageSessionId":"source","transport":"r2","sizeBytes":1024}},
{"itemId":"answer","type":"text","text":"Uploaded"},
{"itemId":"pdf","type":"file","file":{"id":"pdf","fileName":"report.pdf","transport":"local"}}
]}]
"""
var fileTranscript = ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(assistantFiles.utf8)))
let liveFiles = fileTranscript.rows().filter { $0.file != nil }
precondition(liveFiles.map(\.text) == ["clip.mp4", "report.pdf"] && liveFiles.allSatisfy(\.actionable))
precondition(liveFiles.first?.file?.storageSessionId == "source" && liveFiles.first?.file?.sizeBytes == 1024)
fileTranscript.entries[0].finished = true
precondition(fileTranscript.rows().filter { $0.file != nil } == liveFiles)
precondition(fileTranscript.rows(processEntryID: "files").map(\.kind) == ["tool_call"])
precondition(ChatTranscript.previewRows(from: assistantFiles).filter { $0.file != nil } == liveFiles)
fileTranscript.entries[0].items.removeAll { !$0.isAttachment }
precondition(fileTranscript.rows().map(\.kind) == ["file", "file"])
print("MCP files: inline preview actions, completion, standalone upload and cache restore passed")

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
precondition(pendingRows.map(\.kind) == ["attachments", "user", "duration"],
  "A send must show its attachment, text and a separate static duration immediately")
precondition(pendingRows.first?.attachments.first?.localURI == "file:///tmp/cat.png" && pendingRows.last?.running == true)
precondition(pendingRows.last?.id == "local-send:duration")
precondition((2_400...3_000).contains(pendingRows.last?.workDurationMs ?? -1),
  "The local duration must start at submission time")
precondition(ChatWorkDuration.needsTimer(pendingRows),
  "A local duration row must keep advancing before the server replies")
precondition(pendingRows.last?.text == LodyStrings.text("native.chat.transcript.status.confirming"),
  "An unacked send must confirm delivery on the existing duration row")
precondition(pendingRows.last?.text != localPending.status,
  "Phase copy such as uploading must not replace the unacked duration row")
precondition(ChatWorkDuration.needsTimer(liveDurationRows))
precondition(!ChatWorkDuration.needsTimer(finishedDurationRows))
let authoritative = ChatEntry(id: "local-send", role: "user", status: "completed", finished: true, timestamp: nil, endedAt: nil, startedAt: nil, items: [], fileDiffs: nil)
let authoritativeDuration = localPending.rows(entries: [authoritative])
precondition(authoritativeDuration.map(\.kind) == ["duration"],
  "Authoritative user history must replace the pending user row without interrupting duration")
precondition(authoritativeDuration.last?.text != LodyStrings.text("native.chat.transcript.status.confirming"),
  "History takeover must start the working duration on the same row")
var failedPending = localPending
failedPending.failed = true
let failedRows = failedPending.rows(entries: [])
var uploadingPending = localPending
uploadingPending.phase = "sending"
uploadingPending.uploadProgress = ["photo": ChatAttachmentUploadProgress(phase: "uploading", percent: 37)]
let uploadingRows = uploadingPending.rows(entries: [])
precondition(uploadingRows.first?.uploadProgress["photo"]?.percent == 37 && uploadingRows.first?.running == true)
precondition(uploadingRows.first?.attachments == pendingRows.first?.attachments,
  "Progress must not replace attachment identities or restart image loaders")
precondition(uploadingRows.last?.text == LodyStrings.text("native.chat.transcript.status.confirming"),
  "Upload progress must not replace the unacked duration copy")
uploadingPending.phase = "accepted"
let acceptedRows = uploadingPending.rows(entries: [])
precondition(acceptedRows.first?.running == false,
  "An accepted send must stop upload indicators before history arrives")
precondition(acceptedRows.last?.kind == "duration" && acceptedRows.last?.text != LodyStrings.text("native.chat.transcript.status.confirming"),
  "An accepted send must show working duration before history arrives")
precondition(pendingRows.first?.running == true && failedRows.first?.running == false,
  "Loading belongs to attachment tiles and must stop on failure")
precondition(failedRows.first?.attachments == pendingRows.first?.attachments && failedRows.last?.actionable == true,
  "A definite failure must retain the attachment and offer explicit retry")
let flying = ChatPendingSend.hidingStatus(pendingRows, inFlight: ["local-send"])
precondition(flying.map(\.kind) == ["attachments", "user"],
  "A flying send must keep its bubble and hide status until the throw lands")
precondition(ChatPendingSend.hidingStatus(pendingRows, inFlight: []).map(\.kind) == pendingRows.map(\.kind),
  "A send with no flight must show its duration immediately")
precondition(ChatPendingSend.hidingStatus(failedRows, inFlight: ["local-send"]).last?.kind != "pending",
  "Retry must wait for the throw to finish")
precondition(ChatPendingSend.hidingStatus(failedRows, inFlight: []).last?.kind == "pending")
precondition(ChatPendingSend.hidingStatus(authoritativeDuration, inFlight: ["local-send"]).isEmpty,
  "History duration must not appear beside a still-flying bubble")
let neighbor = pendingRows + [ChatRow(id: "other:duration", entryID: "other", kind: "duration", text: "kept")]
precondition(ChatPendingSend.hidingStatus(neighbor, inFlight: ["local-send"]).contains { $0.id == "other:duration" },
  "Another turn's duration must stay visible during this throw")
print("Pending send: immediate text and attachment, processing, stable history takeover and failure passed")

var disconnectedPending = localPending
disconnectedPending.reconnect = true
let reconnectRows = disconnectedPending.rows(entries: [])
precondition(reconnectRows.map(\.kind) == pendingRows.map(\.kind),
  "Connection chrome must not insert a list status row")
precondition(!reconnectRows.contains { $0.kind == "pending" },
  "Waiting for a connection is not a transcript cell")
precondition(reconnectRows.first?.running == false,
  "Reconnection replaces tile loading")
precondition(reconnectRows.firstIndex(where: { $0.kind == "duration" }) == pendingRows.firstIndex(where: { $0.kind == "duration" }),
  "Removing the reconnect row must not shift the reply header")
precondition(reconnectRows.last?.text == LodyStrings.text("native.chat.transcript.status.confirming"),
  "Reconnection must keep the unacked duration copy")
precondition(pendingRows.last?.actionable == false, "Ordinary pending status must not open the execution process")
print("Pending reconnect: connection stays off the transcript passed")

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

func assertReadingColumn(collectionWidth: CGFloat, itemWidth: CGFloat, inset: CGFloat, file: StaticString = #file, line: UInt = #line) {
  precondition(ChatReadingColumn.itemWidth(in: collectionWidth) == itemWidth, "item width", file: file, line: line)
  precondition(ChatReadingColumn.horizontalInset(in: collectionWidth) == inset, "horizontal inset", file: file, line: line)
  precondition(
    ChatReadingColumn.itemWidth(in: collectionWidth) + ChatReadingColumn.horizontalInset(in: collectionWidth) * 2 == collectionWidth
      || collectionWidth <= 1,
    "items plus insets must fill a full-bleed scroll view",
    file: file,
    line: line
  )
}
assertReadingColumn(collectionWidth: 390, itemWidth: 350, inset: 20)
assertReadingColumn(collectionWidth: 800, itemWidth: 760, inset: 20)
assertReadingColumn(collectionWidth: 1180, itemWidth: 760, inset: 210)
precondition(ChatReadingColumn.columnWidth(in: 1180) == 800)
print("Reading column: wide hosts keep a 760 pt column inside a full-bleed scroll view")

let failureJSON = """
[{"id":"error","role":"assistant","status":"completed","finished":true,"items":[
{"itemId":"text","type":"text","text":"Completed answer"},
{"itemId":"failure","type":"system_notice","name":"chat_failed","meta":{"reason":"future_reason","message":"raw error"}}
]}]
"""
let failureRows = ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(failureJSON.utf8))).rows()
precondition(failureRows.contains { $0.kind == "text" && $0.text == "Completed answer" })
precondition(failureRows.contains { $0.kind == "chat_failed" && !$0.actionable && $0.attention })
precondition(!failureRows.contains { $0.kind == "summary" })

precondition(ChatFailure.hasDetail(failureRows.first { $0.kind == "chat_failed" }?.errorMeta))
precondition(!ChatFailure.hasDetail(nil))

// Provider-proven continuation: user bubbles outside one AI-only process.
let guidedJSON = """
[
{"id":"root","role":"user","status":"handled","finished":true,"executionId":"root","executionFinished":true,"items":[{"itemId":"u","type":"text","text":"Original task"}]},
{"id":"before","role":"assistant","status":"handled","finished":true,"executionId":"root","executionFinished":true,"items":[{"itemId":"intro","type":"text","text":"Earlier partial answer"},{"itemId":"tool","type":"tool_call","title":"Inspect","hasDetail":true}]},
{"id":"guide","role":"user","status":"handled","finished":true,"executionId":"root","executionFinished":true,"items":[{"itemId":"u","type":"text","text":"Guide one"}]},
{"id":"after","role":"assistant","status":"handled","finished":true,"executionId":"root","executionFinished":true,"steerCount":1,"items":[{"itemId":"work","type":"thought","text":"Later process"},{"itemId":"answer1","type":"text","text":"Final answer part one"},{"itemId":"answer2","type":"text","text":"Final answer part two"}]}]
"""
var guidedEntries = try JSONDecoder().decode([ChatEntry].self, from: Data(guidedJSON.utf8))
let guidedRows = ChatTranscript(entries: guidedEntries).rows()
assert(guidedRows.map(\.kind) == ["user", "user", "summary", "text", "text", "meta"])
assert(guidedRows.prefix(2).map(\.entryID) == ["root", "guide"])
let guidedProcess = ChatTranscript(entries: guidedEntries).rows(processEntryID: "after", processStartID: "__execution__")
assert(guidedProcess.map(\.itemID) == ["intro", "tool", "work"])
assert(guidedProcess[1].entryID == "before" && guidedProcess[1].actionable)
assert(!guidedProcess.contains { $0.kind == "user" })
let shared = ChatMessageShare.content(in: ChatTranscript(entries: guidedEntries), entryID: "after")!
assert(shared.text == "Final answer part one\n\nFinal answer part two", "Sharing includes all final blocks, never the earlier process")
assert(ChatMessageShare.content(in: ChatTranscript(entries: guidedEntries), entryID: "root") == nil)
var runningShare = guidedEntries
runningShare[runningShare.count - 1].finished = false
assert(ChatMessageShare.content(in: ChatTranscript(entries: runningShare), entryID: "after") == nil)
assert(ChatMessageShare.accepts(height: 6000) && !ChatMessageShare.accepts(height: 6001))
assert(!ChatMessageShare.accepts(height: .infinity))
let roundTrip = try JSONDecoder().decode(ChatMessageShare.self, from: JSONEncoder().encode(shared))
assert(roundTrip.text == shared.text)
for i in guidedEntries.indices { guidedEntries[i].executionFinished = false }
let continuing = ChatTranscript(entries: guidedEntries).rows()
assert(continuing.contains { $0.itemID == "intro" })
assert(!continuing.contains { $0.id == "root:execution" })
print("Steer: user bubbles outside one process, all final text survives, tool owners preserved")

let taskJSON = """
[{"id":"reply","role":"assistant","status":"running","finished":false,"items":[
{"itemId":"think","type":"thought","text":"split work"},
{"itemId":"read","type":"tool_call","kind":"read","title":"读取","status":"completed"},
{"itemId":"explore","type":"subagent_task","taskId":"t1","status":"in_progress","actor":"Explore","description":"Find chrome","lastToolName":"Read"},
{"itemId":"house","type":"subagent_task","taskId":"house","status":"in_progress","actor":"Housekeeping","skipTranscript":true},
{"itemId":"done","type":"subagent_task","taskId":"t0","status":"completed","actor":"Explore","description":"Already finished"}]}]
"""
transcript.entries = try JSONDecoder().decode([ChatEntry].self, from: Data(taskJSON.utf8))
assert(transcript.liveSubagentItems().map(\.itemId) == ["explore"])
assert(!transcript.rows().contains { $0.kind == "subagent_task" || $0.itemID == "explore" || $0.itemID == "house" })
assert(transcript.rows().contains { $0.kind == "summary" })
let processTasks = transcript.rows(processEntryID: "reply")
assert(processTasks.contains { $0.itemID == "explore" && $0.kind == "subagent_task" })
assert(processTasks.contains { $0.itemID == "done" && $0.kind == "subagent_task" })
assert(!processTasks.contains { $0.itemID == "house" })
assert(transcript.rows(processEntryID: "reply", processStartID: "__tasks__").map(\.itemID) == ["explore", "done"])
transcript.entries[0].finished = true
assert(!transcript.rows().contains { $0.kind == "subagent_task" || $0.itemID == "explore" })
print("Chat: live subagent tasks stay off the main list and skip housekeeping")

let screen = ChatImagePreviewGeometry.Size(width: 400, height: 800)
assert(
  ChatImagePreviewGeometry.fitContain(ChatImagePreviewGeometry.Size(width: 1600, height: 900), in: screen)
    == ChatImagePreviewGeometry.Rect(x: 0, y: 287.5, width: 400, height: 225),
  "A wide picture fits the screen width and stays centred"
)
assert(
  ChatImagePreviewGeometry.fitContain(ChatImagePreviewGeometry.Size(width: 1000, height: 4000), in: screen)
    == ChatImagePreviewGeometry.Rect(x: 100, y: 0, width: 200, height: 800),
  "A tall picture fits the screen height and stays centred"
)
assert(
  ChatImagePreviewGeometry.fitContain(.zero, in: screen)
    == ChatImagePreviewGeometry.Rect(x: 0, y: 0, width: 400, height: 800),
  "An unknown size fills the box instead of vanishing"
)
let box = ChatImagePreviewGeometry.box(
  viewport: screen, safeTop: 62, safeBottom: 34, inset: 16
)
assert(box.x == 16 && box.width == 368)
assert(box.y == 62 + 16 && box.height == 800 - 2 * (62 + 16), "Vertical inset uses the larger safe edge so the picture stays centred")
let fitted = ChatImagePreviewGeometry.fitWithin(ChatImagePreviewGeometry.Size(width: 1600, height: 900), in: box)
assert(fitted.x == box.x && fitted.width == box.width)
assert(fitted.y + fitted.height / 2 == box.y + box.height / 2)

let width: CGFloat = 416
assert(ChatImagePreviewGeometry.snapPage(offset: -100, velocity: 0, current: 0, count: 5, pageWidth: width) == 0)
assert(ChatImagePreviewGeometry.snapPage(offset: -100, velocity: -1200, current: 0, count: 5, pageWidth: width) == 1)
assert(ChatImagePreviewGeometry.snapPage(offset: -300, velocity: 0, current: 0, count: 5, pageWidth: width) == 1)
assert(ChatImagePreviewGeometry.snapPage(offset: -width * 3, velocity: -8000, current: 1, count: 5, pageWidth: width) == 2)
assert(ChatImagePreviewGeometry.snapPage(offset: 50, velocity: 900, current: 0, count: 5, pageWidth: width) == 0)
assert(ChatImagePreviewGeometry.snapPage(offset: 0, velocity: 0, current: 0, count: 1, pageWidth: width) == 0)

let hit = ChatImagePreviewGeometry.Rect(x: 0, y: 287.5, width: 400, height: 225)
assert(ChatImagePreviewGeometry.hits(CGPoint(x: 200, y: 400), rect: hit, scale: 1, translation: .zero))
assert(!ChatImagePreviewGeometry.hits(CGPoint(x: 200, y: 100), rect: hit, scale: 1, translation: .zero))
assert(ChatImagePreviewGeometry.hits(CGPoint(x: 200, y: 100), rect: hit, scale: 3, translation: .zero))

let clamped = ChatImagePreviewGeometry.rubberBandClamp(300, min: 0, max: 100, dimension: 400)
assert(clamped > 100 && clamped < 300, "Overshoot must resist without reaching the push")
assert(ChatImagePreviewGeometry.panBound(fitted: 400, scale: 1, viewport: 400) == 0)
assert(ChatImagePreviewGeometry.panBound(fitted: 400, scale: 2, viewport: 400) == 200)
assert(!ChatImagePreviewGeometry.shouldPage(zoomScale: 1, velocity: CGPoint(x: 0, y: 400), count: 3))
assert(!ChatImagePreviewGeometry.shouldPage(zoomScale: 2, velocity: CGPoint(x: 400, y: 0), count: 3))
assert(!ChatImagePreviewGeometry.shouldPage(zoomScale: 1, velocity: CGPoint(x: 400, y: 0), count: 1))
assert(ChatImagePreviewGeometry.shouldPage(zoomScale: 1, velocity: CGPoint(x: 400, y: 0), count: 3))
print("Image preview geometry: fit, paging snap, hit testing and rubber-band passed")

let userPhoto = ChatImage(id: "image1", fileName: "sample.png", storageSessionId: nil, width: 800, height: 600)
let fileOnly = ChatMessageAttachment(id: "notes", fileName: "notes.txt")
let photoAttachment = ChatMessageAttachment(id: "image1", fileName: "sample.png", image: userPhoto, localURI: "file:///tmp/sample.png")
let mixedRows = [
  ChatRow(id: "turn:user", entryID: "turn", kind: "attachments", text: "", attachments: [fileOnly, photoAttachment]),
  ChatRow(id: "turn:user-text", entryID: "turn", kind: "user", text: "caption"),
  ChatRow(
    id: "reply:photos:image:0", entryID: "reply", kind: "image", text: "", itemID: "photos",
    image: ChatImage(id: "one", fileName: "one.png", storageSessionId: "source", width: 600, height: 400)
  ),
  ChatRow(
    id: "reply:photos:image:1", entryID: "reply", kind: "image", text: "", itemID: "photos",
    image: ChatImage(id: "two", fileName: "two.png", storageSessionId: nil, width: nil, height: nil)
  ),
]
let gallery = ChatImageGallery.items(from: mixedRows)
assert(gallery.map(\.id) == ["turn:attachment:image1", "reply:photos:image:0", "reply:photos:image:1"])
assert(gallery.map(\.image.id) == ["image1", "one", "two"])
assert(gallery.first?.localURI == "file:///tmp/sample.png")
assert(ChatImageGallery.items(from: mixedRows.filter { $0.kind == "user" }).isEmpty)
assert(ChatImageGallery.index(of: "reply:photos:image:1", in: gallery) == 2)
assert(ChatImageGallery.index(of: "missing", in: gallery) == nil)
let userAlbum = ChatImageGallery.items(from: [
  ChatRow(
    id: "turn:user", entryID: "turn", kind: "attachments", text: "",
    attachments: [
      ChatMessageAttachment(id: "ui-verify-image", fileName: "fixture.png", image: userPhoto),
      ChatMessageAttachment(
        id: "ui-verify-image-1", fileName: "two.png",
        image: ChatImage(id: "ui-verify-image-1", fileName: "two.png", storageSessionId: nil, width: 400, height: 600)
      ),
      ChatMessageAttachment(
        id: "ui-verify-image-2", fileName: "three.png",
        image: ChatImage(id: "ui-verify-image-2", fileName: "three.png", storageSessionId: nil, width: 600, height: 400)
      ),
    ]
  ),
])
assert(userAlbum.map(\.id) == [
  "turn:attachment:ui-verify-image",
  "turn:attachment:ui-verify-image-1",
  "turn:attachment:ui-verify-image-2",
])
print("Image gallery: list order, skip files, attachment ids, and lookup passed")
