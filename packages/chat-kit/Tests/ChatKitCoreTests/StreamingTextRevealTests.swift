import ChatKitCore
import Testing

@Test func correctionReplacesPendingText() {
  var stream = CKTextReveal()
  stream.receive("Initial", animate: false, at: 0)
  stream.receive("Initial appended text", animate: true, at: 1)
  #expect(stream.hasPending)
  stream.receive("Corrected", animate: true, at: 1.01)
  stream.advance(at: 2)
  #expect(stream.shown == "Corrected")
  #expect(!stream.hasPending)
}

@Test func unicodeAppendAndFinishPreserveExactContent() {
  let text = "👩🏽‍💻 café\nمرحبا 世界"
  var stream = CKTextReveal()
  stream.receive(text, animate: true, at: 1)
  stream.advance(at: 1.02)
  #expect(text.hasPrefix(stream.shown))
  stream.finish()
  #expect(stream.shown == text)
  #expect(!stream.hasPending)
}

@Test func independentStreamsAndAnimationDisable() {
  var first = CKTextReveal()
  var second = CKTextReveal()
  first.receive("First reply", animate: true, at: 1)
  second.receive("Second reply", animate: true, at: 1)
  first.receive("First reply", animate: false, at: 1.01)
  #expect(first.shown == "First reply")
  #expect(second.shown.isEmpty)
  #expect(second.hasPending)
  second.advance(at: 2)
  #expect(second.shown == "Second reply")
}
