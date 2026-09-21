import Foundation

/// Only in-flight rendered graphemes carry animation state. Markdown edits
/// preserve their birth times; ordinary appends never diff the completed text.
struct ChatTextFade {
  static let duration = 0.18
  struct RangeFade {
    let range: NSRange
    let start: Double
    func opacity(at time: Double) -> Double {
      let progress = min(1, max(0, (time - start) / ChatTextFade.duration))
      return progress * progress * (3 - 2 * progress)
    }
  }
  private var text = ""
  private var length = 0
  private var lastUpdate: Double?
  private(set) var active: [RangeFade] = []

  mutating func update(_ text: String, animate: Bool, at time: Double, reset: Bool = false) {
    // MarkdownView terminates paragraphs with a synthetic newline. Ignore that
    // invisible terminator so appends still take the suffix-only path.
    let next = text.last?.isNewline == true ? String(text.dropLast()) : text
    active.removeAll { $0.opacity(at: time) >= 1 }
    if reset || !animate {
      self.text = next
      length = next.utf16.count
      lastUpdate = time
      active = []
      return
    }
    guard next != self.text else { return }
    let gap = min(0.096, max(0.016, time - (lastUpdate ?? time)))
    lastUpdate = time
    var inserted: [NSRange] = []
    if next.hasPrefix(self.text) {
      var offset = length
      for character in String(decoding: next.utf16.dropFirst(length), as: UTF16.self) {
        let count = String(character).utf16.count
        inserted.append(NSRange(location: offset, length: count))
        offset += count
      }
      length = offset
    } else {
      // Syntax closure can remove delimiters or change earlier rendered text.
      // Diff only on that path; completed characters need no birth-time array.
      let previous = Array(self.text)
      let characters = Array(next)
      var removed: Set<Int> = []
      var added: Set<Int> = []
      for change in characters.difference(from: previous) {
        switch change {
        case .remove(let index, _, _): removed.insert(index)
        case .insert(let index, _, _): added.insert(index)
        }
      }
      var oldBirths: [Int: Double] = [:]
      var offset = 0
      var fadeIndex = 0
      for (index, character) in previous.enumerated() {
        while fadeIndex < active.count && NSMaxRange(active[fadeIndex].range) <= offset { fadeIndex += 1 }
        if fadeIndex < active.count, NSLocationInRange(offset, active[fadeIndex].range) {
          oldBirths[index] = active[fadeIndex].start
        }
        offset += String(character).utf16.count
      }
      active = []
      var oldIndex = 0
      offset = 0
      for (index, character) in characters.enumerated() {
        let count = String(character).utf16.count
        let range = NSRange(location: offset, length: count)
        if added.contains(index) {
          inserted.append(range)
        } else {
          while removed.contains(oldIndex) { oldIndex += 1 }
          if let birth = oldBirths[oldIndex] { active.append(RangeFade(range: range, start: birth)) }
          oldIndex += 1
        }
        offset += count
      }
      length = offset
    }
    self.text = next
    // ponytail: group large appends into at most 128 fades; individual glyph
    // animation can return if measured drawing cost permits it.
    let groupSize = max(1, Int(ceil(Double(inserted.count) / 128)))
    let groups = max(1, Int(ceil(Double(inserted.count) / Double(groupSize))))
    let firstBirth = min(time + gap, max(time, active.map(\.start).max() ?? time))
    for index in stride(from: 0, to: inserted.count, by: groupSize) {
      let end = min(inserted.count, index + groupSize) - 1
      let range = NSUnionRange(inserted[index], inserted[end])
      let birth = min(time + gap, firstBirth + Double(index / groupSize) * gap / Double(groups))
      if range.length == inserted[index...end].reduce(0, { $0 + $1.length }) {
        active.append(RangeFade(range: range, start: birth))
      } else {
        // Never animate surviving text between separate insertions.
        for item in inserted[index...end] { active.append(RangeFade(range: item, start: birth)) }
      }
    }
    active.sort { $0.range.location < $1.range.location }
  }

  func isAnimating(at time: Double) -> Bool { active.contains { $0.opacity(at: time) < 1 } }
}
