import Foundation

@MainActor
func verify() {
  var time: TimeInterval = 100
  var entered: [(String, Data)] = []
  var exited: [String] = []
  var polls = 0
  let registration = LiveActivityRegistration(
    enter: { entered.append(($0, $1)) }, exit: { exited.append($0) },
    restart: { polls += 1 }, now: { time }
  )
  let old = UUID(), replacement = UUID(), other = UUID()
  let token = Data([1]), rotated = Data([2])
  registration.observe("a", stamp: old)
  registration.enter("a", token: token, stamp: old)
  registration.enter("a", token: token, stamp: old)
  precondition(entered.count == 1 && polls == 1, "duplicate token events do not enqueue extra submissions")

  registration.recover()
  precondition(entered.count == 2 && polls == 1, "foreground re-submits current token; poll bursts are throttled")
  time += 30
  registration.recover()
  precondition(entered.count == 3 && polls == 2, "cached failures need the SDK poll, not a fake success callback")

  registration.observe("a", stamp: replacement)
  registration.enter("a", token: token, stamp: old)
  precondition(entered.count == 3, "old observer cannot overwrite a replacement token")
  registration.enter("a", token: rotated, stamp: replacement)
  precondition(entered.count == 4 && entered.last!.1 == rotated && exited.isEmpty,
               "same server ID replacement must not queue DELETE before its new POST")

  registration.observe("b", stamp: other)
  registration.enter("b", token: token, stamp: other)
  registration.exit("a")
  registration.enter("a", token: rotated, stamp: replacement)
  precondition(exited == ["a"] && entered.count == 5, "ending invalidates late token events")
  time += 30
  registration.recover()
  precondition(entered.count == 6 && entered.last!.0 == "b" && polls == 3,
               "foreground cannot resurrect an ended activity and preserves other IDs")

  registration.exit("b")
  let count = entered.count
  time += 30
  registration.recover()
  precondition(entered.count == count && polls == 4, "cleanup can retry without re-registering ended tokens")
  print("PASS: token deduplication, foreground resubmission, SDK cache recovery throttling, replacement without exit, stale observer fencing and end cleanup")
}

MainActor.assumeIsolated { verify() }
