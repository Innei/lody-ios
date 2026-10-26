import Foundation

@MainActor
func code(_ work: () async throws -> Void) async -> String {
  do {
    try await work()
    return ""
  } catch {
    return (error as NSError).localizedDescription
  }
}

@MainActor
func run() async {
  var sent: [[String: Any]] = []
  let emit: ([String: Any]) -> Void = { sent.append($0) }

  let answered = Task { await code { try await LodyNavRequest.send(["type": "callback"], key: "callback:1:onCreated", timeout: nil, via: emit) } }
  await Task.yield()
  let first = sent[0]["id"] as! String
  precondition(LodyNavRequest.busy("callback:1:onCreated"))
  let refused = await code { try await LodyNavRequest.send(["type": "callback"], key: "callback:1:onCreated", timeout: nil, via: emit) }
  precondition(refused == "request_in_flight", "A second request for the same page and name must be refused: \(refused)")
  precondition(sent.count == 1, "A refused request must not reach React")
  LodyNavRequest.reply(first, error: "")
  let answeredCode = await answered.value
  precondition(answeredCode == "", "A reply settles the request")
  precondition(!LodyNavRequest.busy("callback:1:onCreated"))

  let failed = Task { await code { try await LodyNavRequest.send([:], key: "callback:2:onCreated", timeout: nil, via: emit) } }
  await Task.yield()
  LodyNavRequest.reply(sent[1]["id"] as! String, error: "open_failed")
  let failedCode = await failed.value
  precondition(failedCode == "open_failed", "A React error reaches the caller")

  let closed = Task { await code { try await LodyNavRequest.send([:], key: "callback:3:onCreated", timeout: nil, via: emit) } }
  await Task.yield()
  LodyNavRequest.reset(prefix: "callback:3:")
  let closedCode = await closed.value
  precondition(closedCode == "request_reset", "Closing the page settles its pending callback")
  LodyNavRequest.reply(sent[2]["id"] as! String, error: "late")
  precondition(!LodyNavRequest.busy("callback:3:onCreated"), "A late reply after close is ignored")

  let timedOut = await code { try await LodyNavRequest.send([:], key: "preview:x", timeout: .milliseconds(50), via: emit) }
  precondition(timedOut == "request_timeout", "An unanswered request times out: \(timedOut)")
  LodyNavRequest.reply(sent[3]["id"] as! String, error: "")

  let unavailable = await code { try await LodyNavRequest.send([:], key: "preview:y", timeout: nil, via: nil) }
  precondition(unavailable == "nav_unavailable")
  print("PASS: one request per key, replies, errors, reset on close, late replies ignored, timeout")
}

await run()
