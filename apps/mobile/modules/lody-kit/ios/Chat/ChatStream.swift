import Foundation

/// Presentation-only pacing, driven by elapsed time and input pressure.
/// Network history remains authoritative, including corrections and completion.
struct ChatStream {
  private struct Reveal {
    var source = ""
    var shown = ""
    var pending: [Character] = []
    var offset = 0
    var lastInput: Double?
    var lastAdvance = 0.0
    var arrivalRate = 38.0
    var hasPending: Bool { offset < pending.count }

    mutating func receive(_ text: String, animate: Bool, at time: Double) {
      guard text != source else {
        if !animate { finish() }
        return
      }
      guard animate, text.hasPrefix(source) else {
        source = text
        finish()
        lastInput = nil
        arrivalRate = 38
        return
      }
      let appended = Array(text.dropFirst(source.count))
      if let lastInput {
        let rate = Double(appended.count) / max(0.016, time - lastInput)
        arrivalRate += (rate - arrivalRate) * 0.35
      }
      if !hasPending { lastAdvance = time }
      lastInput = time
      pending = Array(pending.dropFirst(offset)) + appended
      offset = 0
      source = text
    }
    mutating func advance(at time: Double) {
      guard hasPending else { return }
      let elapsed = min(0.12, max(0, time - lastAdvance))
      guard elapsed > 0 else { return }
      lastAdvance = time
      let backlog = pending.count - offset
      // Drain bursts within a short time budget, independent of message length.
      let speed = max(38, arrivalRate * 1.1, Double(backlog) / 0.18)
      var batch = max(1, Int(speed * elapsed))
      if time - (lastInput ?? time) >= 0.45 || backlog > 2048 { batch = backlog }
      let end = min(pending.count, offset + batch)
      shown += String(pending[offset..<end])
      offset = end
      if !hasPending { finish() }
    }
    mutating func finish() {
      shown = source
      pending.removeAll(keepingCapacity: false)
      offset = 0
    }
  }

  private struct ID: Hashable { let entry: String; let item: String }
  private var reveals: [ID: Reveal] = [:]
  private var targets: [ChatEntry] = []
  private var initialized = false
  private var settling: Set<String> = []
  var hasPending: Bool { !settling.isEmpty || reveals.values.contains { $0.hasPending } }

  static func commitInterval(tailLength: Int) -> Double {
    min(0.096, 0.048 * (1 + Double(tailLength) / 256))
  }

  mutating func receive(_ entries: [ChatEntry], animate: Bool, at time: Double = ProcessInfo.processInfo.systemUptime) {
    let wasRunning = Set(targets.filter(\.isRunning).map(\.id))
    var retained: Set<ID> = []
    for entry in entries where entry.role != "user" {
      for item in entry.items where item.type == "text" || item.type == "thought" {
        let id = ID(entry: entry.id, item: item.itemId)
        retained.insert(id)
        var reveal = reveals[id] ?? Reveal()
        let shouldAnimate = initialized && animate && entry.role == "assistant" && (entry.isRunning || wasRunning.contains(entry.id) || reveal.hasPending)
        reveal.receive(item.text ?? "", animate: shouldAnimate, at: time)
        reveals[id] = reveal
      }
    }
    reveals = reveals.filter { retained.contains($0.key) }
    targets = entries
    settling.formIntersection(entries.map(\.id))
    if !animate { settling.removeAll() }
    initialized = true
  }

  mutating func advance(at time: Double = ProcessInfo.processInfo.systemUptime, animatingEntries: Set<String> = []) {
    let completed = Set(targets.filter { !$0.isRunning }.map(\.id))
    settling = animatingEntries.intersection(completed)
    for id in reveals.keys {
      let before = reveals[id]?.shown
      reveals[id]?.advance(at: time)
      // Let the final commit reach the renderer before asking whether it faded.
      if completed.contains(id.entry), before != reveals[id]?.shown { settling.insert(id.entry) }
    }
  }

  mutating func finish() {
    settling.removeAll()
    for id in reveals.keys { reveals[id]?.finish() }
  }

  var presentation: [ChatEntry] {
    targets.map { target in
      var entry = target
      for index in entry.items.indices {
        guard let reveal = reveals[ID(entry: entry.id, item: entry.items[index].itemId)] else { continue }
        entry.items[index].text = reveal.shown
        // Completion folding waits for the visible tail, never the network ACK.
        if reveal.hasPending || settling.contains(entry.id) { entry.finished = false }
      }
      return entry
    }
  }
}

enum ChatScroll {
  static let resumeDistance: Double = 80

  // Time-based convergence keeps a moving destination continuous across updates
  // and behaves the same at 60 and 120 Hz. Snap only a subpixel remainder.
  static func advance(_ current: Double, toward target: Double, elapsed: Double, response: Double, minimumStep: Double = 0) -> Double {
    let next = current + (target - current) * (1 - exp(-max(0, elapsed) / response))
    // UIScrollView rounds offsets to its pixel grid. A step smaller than one
    // pixel can otherwise round back forever while the display link keeps firing.
    if elapsed > 0 && abs(next - current) < minimumStep { return target }
    return abs(target - next) <= 0.5 ? target : next
  }

  static func bottom(contentHeight: Double, viewportHeight: Double, topInset: Double, bottomInset: Double) -> Double {
    max(-topInset, contentHeight - viewportHeight + bottomInset)
  }
}
