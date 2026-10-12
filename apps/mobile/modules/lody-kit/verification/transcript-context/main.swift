import Foundation

func transcript(_ value: String) throws -> ChatTranscript {
  ChatTranscript(entries: try JSONDecoder().decode([ChatEntry].self, from: Data(value.utf8)))
}

let usageJSON = #"[{"id":"with-usage","role":"assistant","status":"completed","finished":true,"tokenUsage":{"inputTokens":1234,"outputTokens":6640,"cacheReadInputTokens":120000,"cacheCreationInputTokens":4096,"reasoningOutputTokens":2000},"items":[{"itemId":"answer","type":"text","text":"Reported usage"}]},{"id":"without-usage","role":"assistant","status":"completed","finished":true,"items":[{"itemId":"answer","type":"text","text":"No reported usage"}]}]"#
let usage = try transcript(usageJSON)
precondition(usage.entries[0].tokenUsage?.total == 133970)
precondition(usage.rows().first { $0.id == "with-usage:meta" }?.text.contains("native.chat.usage.tokens") == true)
precondition(usage.rows().first { $0.id == "without-usage:meta" }?.text == "", "Missing telemetry must not invent zero tokens")
precondition(ChatTokenUsage(inputTokens: -1, outputTokens: 1, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, reasoningOutputTokens: 0).total == nil)
precondition(ChatTokenUsage(inputTokens: Int.max, outputTokens: 1, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, reasoningOutputTokens: 0).total == nil)

let warningJSON = #"[{"id":"reply","role":"assistant","status":"completed","finished":true,"items":[{"itemId":"warning","type":"system_notice","name":"agent_warning","meta":{"message":"The provider is retrying."}},{"itemId":"tool","type":"tool_call","title":"Read file","status":"completed"},{"itemId":"answer","type":"text","text":"Ready"}]}]"#
let warning = try transcript(warningJSON)
let warningRows = warning.rows()
precondition(warningRows.first?.kind == "system_notice")
precondition(warningRows.first?.text == "The provider is retrying.")
precondition(warningRows.first?.attention == false, "Agent warnings use the secondary system style")
precondition(!warning.rows(processEntryID: "reply").contains { $0.itemID == "warning" }, "Warnings must stay out of the execution process")
precondition(warningRows.contains { $0.kind == "summary" } && warningRows.contains { $0.kind == "text" })

let fileJSON = #"[{"id":"reply","role":"assistant","status":"completed","finished":true,"items":[{"itemId":"file","type":"file","file":{"id":"artifact","fileName":"report.pdf","transport":"r2","sizeBytes":2048,"uploadedAt":1900000000000}},{"itemId":"pending","type":"file","file":{"id":"local","fileName":"draft.pdf","transport":"local"}}]}]"#
let files = try transcript(fileJSON)
let available = files.rows(now: 1900000000001)
precondition(available.first?.file?.id == "artifact" && available.first?.actionable == true)
precondition(available.last?.file?.id == "local" && available.last?.actionable == false)
precondition(files.rows(now: 1900000000000 + 91 * 86400000).first?.actionable == false, "Expired relay artifacts cannot offer a working download")

let teamJSON = #"[{"id":"human","role":"user","status":"handled","finished":true,"userId":"maya","items":[{"itemId":"input","type":"text","text":"Review"}]},{"id":"agent","role":"user","status":"handled","finished":true,"author":{"kind":"agent","name":"Codex","role":{"name":"Reviewer","emoji":"🔎"}},"items":[{"itemId":"input","type":"text","text":"Agent-authored reply"}]}]"#
var team = try transcript(teamJSON)
team.senders = ["maya": "Maya Chen"]
precondition(!team.rows().contains { $0.id == "human:sender" }, "Solo workspaces do not spend a row on human identity")
precondition(team.rows().contains { $0.id == "agent:sender" && $0.text == "🔎 Reviewer" }, "Frozen Role authors remain visible in solo workspaces")
team.showSenderIdentity = true
precondition(team.rows().contains { $0.id == "human:sender" && $0.text == "Maya Chen" })
team.senders = [:]
precondition(!team.rows().contains { $0.id == "human:sender" }, "An unresolved team member must not display an opaque user id as a name")

let goalsJSON = #"[{"id":"goal","role":"assistant","status":"completed","finished":true,"items":[{"itemId":"active","type":"goal","goal":{"threadId":"thread","objective":"Fix the repair","status":"active"}},{"itemId":"paused","type":"goal","goal":{"threadId":"thread","objective":"Fix the repair","status":"paused"}}]}]"#
let goals = try transcript(goalsJSON)
var context = ChatSessionContext()
context.goal = ChatGoal(threadId: "fallback", objective: "Stale fallback", status: "active", tokenBudget: nil, tokensUsed: nil, timeUsedSeconds: nil)
context.contextWindowUsage = ChatContextWindowUsage(size: 200000, used: 0)
var contextRows = goals.contextRows(context)
precondition(contextRows[0].text == "native.chat.goal.paused" && contextRows[0].contextDetail == "Fix the repair")
precondition(contextRows.contains { $0.id == "session-context-usage" })
precondition(!goals.rows().contains { $0.kind == "goal" || $0.kind == "summary" }, "Goal updates belong to the current banner, never the process")
let clearedGoals = try transcript(goalsJSON.replacingOccurrences(of: "paused", with: "cleared"))
context.dismissedGoalThreadId = "thread"
precondition(!clearedGoals.contextRows(context).contains { $0.kind == "goal" })
context.contextWindowUsage = ChatContextWindowUsage(size: 0, used: 0)
precondition(!clearedGoals.contextRows(context).contains { $0.kind == "context" }, "Invalid context leaves no visible placeholder")

let scheduleJSON = #"{"scheduledTasks":[{"id":"one","kind":"wakeup","createdAtMs":1000,"scheduledForMs":5000,"summary":"Check again"},{"id":"daily","kind":"cron","createdAtMs":1000,"humanSchedule":"0 9 * * 1-5","recurring":true,"timeZone":"Asia/Tokyo"}]}"#
let schedules = try JSONDecoder().decode(ChatSessionContext.self, from: Data(scheduleJSON.utf8))
precondition(ChatTranscript().contextRows(schedules, now: 4000).count == 2)
precondition(ChatTranscript().contextRows(schedules, now: 8000).map(\.id) == ["session-scheduled:daily"], "Fired wakeups clear without inventing recurring execution")
let legacyScheduleJSON = #"{"scheduledTasks":[{"id":"legacy","kind":"cron","createdAtMs":1000,"nextFireMs":5000,"humanSchedule":"0 9 * * *","recurring":false},{"id":"recurring","kind":"cron","createdAtMs":1000,"nextFireMs":2000,"humanSchedule":"0 9 * * *","recurring":true}]}"#
let legacySchedules = try JSONDecoder().decode(ChatSessionContext.self, from: Data(legacyScheduleJSON.utf8))
precondition(legacySchedules.needsTimer(now: 4000) && legacySchedules.needsTimer(now: 6999),
  "Legacy one-shot cron resolution must start the same native timer as a committed fire time")
precondition(!legacySchedules.needsTimer(now: 7000), "Fired one-shot summaries release the timer after the shared grace period")
precondition(ChatTranscript().contextRows(legacySchedules, now: 4000).map(\.id) == ["session-scheduled:legacy", "session-scheduled:recurring"])
precondition(ChatTranscript().contextRows(legacySchedules, now: 7000).map(\.id) == ["session-scheduled:recurring"],
  "A legacy one-shot clears at its resolved fire time while recurring jobs remain visible")
precondition(warning.readOnlyRows().contains { $0.itemID == "tool" } && !warning.readOnlyRows().contains { $0.kind == "summary" }, "Read-only subtask records keep the complete process visible")
let unknownJSON = #"[{"id":"reply","role":"assistant","status":"completed","finished":true,"items":[{"itemId":"task","type":"subagent_task","status":"completed","run":{"snapshot":{"state":"unknown","name":"Reviewer","reason":{"message":"Observation was lost."}}}}]}]"#
let unknown = try transcript(unknownJSON)
precondition(unknown.rows().first?.subagent?.status == "unknown", "A stale completed task must not override authoritative unknown run state")
precondition(unknown.rows().first?.subagent?.detail == "Observation was lost.")
precondition(unknown.liveSubagentItems().isEmpty)

print("Transcript context: reported tokens, absent telemetry, warnings outside process, file lifecycle, sender isolation, goal precedence and pending schedules passed")
