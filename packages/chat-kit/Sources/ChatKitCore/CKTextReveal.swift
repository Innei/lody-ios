import Foundation

/// Display pacing for one text block. The host retains authoritative content and completion state.
public struct CKTextReveal {
  public init() {}
  public private(set) var source = ""
  public private(set) var shown = ""
  private var pending: [Character] = []
  private var offset = 0
  private var lastInput: Double?
  private var lastAdvance = 0.0
  private var arrivalRate = 38.0
  public var hasPending: Bool { offset < pending.count }

  public mutating func receive(_ text: String, animate: Bool, at time: Double) {
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
  public mutating func advance(at time: Double) {
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
  public mutating func finish() {
    shown = source
    pending.removeAll(keepingCapacity: false)
    offset = 0
  }
}
