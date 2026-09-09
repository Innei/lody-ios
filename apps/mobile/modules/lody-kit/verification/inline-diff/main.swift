import UIKit

func lines(_ document: InlineDiffDocument) -> [InlineDiffLine] {
  document.hunks.flatMap(\.lines)
}

func texts(_ document: InlineDiffDocument) -> [String] {
  lines(document).map { kind in
    let name: String
    switch kind.kind {
    case .context: name = "context"
    case .insert: name = "insert"
    case .delete: name = "delete"
    }
    return "\(name):\(kind.text)"
  }
}

// A replace of one unique line must stay in file order: context, delete, insert, context.
do {
  let document = InlineDiffModel.build(old: "a\nb\nc\n", new: "a\nhello\nc\n")
  precondition(texts(document) == [
    "context:a",
    "delete:b",
    "insert:hello",
    "context:c",
  ])
  let changed = lines(document).filter { $0.kind != .context }
  precondition(changed.count == 2)
  precondition(!changed[0].emphasis.isEmpty)
  precondition(!changed[1].emphasis.isEmpty)
}

// Repeated identical lines must not swap later copies.
do {
  let document = InlineDiffModel.build(old: "x\nx\ny\n", new: "x\nz\ny\n")
  precondition(texts(document) == [
    "context:x",
    "delete:x",
    "insert:z",
    "context:y",
  ])
}

// Empty old file is a pure insert; empty new file is a pure delete.
do {
  let added = InlineDiffModel.build(old: "", new: "only\n")
  precondition(texts(added) == ["insert:only"])
  let removed = InlineDiffModel.build(old: "gone\n", new: "")
  precondition(texts(removed) == ["delete:gone"])
}

// Unicode grapheme clusters stay intact as one token.
do {
  let document = InlineDiffModel.build(old: "café\n", new: "cafés\n")
  precondition(texts(document) == ["delete:café", "insert:cafés"])
}

// Distant edits become two hunks; each keeps three context lines.
do {
  let old = (1...20).map { "line-\($0)" }.joined(separator: "\n") + "\n"
  let newLines = (1...20).map { $0 == 2 || $0 == 18 ? "changed-\($0)" : "line-\($0)" }
  let document = InlineDiffModel.build(old: old, new: newLines.joined(separator: "\n") + "\n")
  precondition(document.hunks.count == 2)
  precondition(lines(document).contains { $0.text == "line-1" })
  precondition(lines(document).contains { $0.text == "line-20" })
  precondition(!lines(document).contains { $0.text == "line-10" })
}

// Identical files still show the body so an empty-looking block is not blank.
do {
  let document = InlineDiffModel.build(old: "same\n", new: "same\n")
  precondition(texts(document) == ["context:same"])
}

let renderer = InlineDiffRenderer(frame: CGRect(x: 0, y: 0, width: 320, height: 10))
renderer.render(
  InlineDiffModel.build(old: "short\n", new: "short\nvery-long-identifier-that-needs-horizontal-scroll\n"),
  path: "demo.ts",
  highlight: false
)
renderer.bounds.size.height = renderer.contentHeight
renderer.layoutIfNeeded()
precondition(renderer.contentHeight > 40, "Renderer must report full stacked height")
precondition(!renderer.allowsVerticalScrolling, "Inline diff must not scroll vertically")
precondition(renderer.allowsHorizontalScrolling, "Long lines must scroll horizontally")
precondition(
  renderer.lineViews.allSatisfy { abs($0.bounds.height - 20) < 0.5 },
  "Code rows must share the 20 pt line box"
)
let origins = renderer.lineViews.map { $0.convert($0.bounds, to: renderer).minY }
if origins.count >= 2 {
  precondition(abs((origins[1] - origins[0]) - 20) < 0.5, "Adjacent rows must sit on a 20 pt grid")
}
precondition(!renderer.rowProbes.isEmpty, "Rendered rows must expose alignment probes")
for probe in renderer.rowProbes {
  precondition(abs(probe.row.height - 20) < 0.5, "Each row is a 20 pt box")
  precondition(abs(probe.gutter.minY - probe.code.minY) < 0.5, "Gutter tint must share the code band origin")
  precondition(abs(probe.gutter.height - probe.code.height) < 0.5, "Gutter tint must share the code band height")
  precondition(abs(probe.bar.minY - probe.gutter.minY) < 0.5, "Change bar must share the gutter origin")
  precondition(abs(probe.bar.height - probe.gutter.height) < 0.5, "Change bar must share the gutter height")
  precondition(abs(probe.number.minY - probe.code.minY) < 0.5, "Line numbers must share the code origin")
  precondition(abs(probe.number.height - probe.code.height) < 0.5, "Line numbers must share the code height")
}
let numberXs = Set(renderer.rowProbes.map { $0.number.minX.rounded() })
let codeXs = Set(renderer.rowProbes.map { $0.code.minX.rounded() })
precondition(numberXs.count == 1, "Every line number must sit on the same left column")
precondition(codeXs.count == 1, "Every code band must share one left edge")

// Additions read as system blue and deletions as system red in both
// appearances: no green accent may leak into either tint.
func channels(_ color: UIColor, _ style: UIUserInterfaceStyle) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
  var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
  color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
  return (r, g, b, a)
}

for style in [UIUserInterfaceStyle.light, .dark] {
  for kind in [InlineDiffLine.Kind.insert, .delete] {
    let tints = [
      InlineDiffRenderer.gutterTint(for: kind),
      InlineDiffRenderer.lineTint(for: kind),
      InlineDiffRenderer.emphasisTint(for: kind),
      InlineDiffRenderer.barColor(for: kind),
    ]
    for tint in tints {
      let parts = channels(tint, style)
      let dominant = kind == .insert ? parts.b : parts.r
      precondition(dominant > parts.g, "\(kind) tint must not be green: \(parts)")
    }
    let alphas = tints.dropLast().map { channels($0, style).a }
    precondition(alphas == alphas.sorted(), "Gutter fade must stay quieter than line and word fades")
  }
  for kind in [InlineDiffLine.Kind.context] {
    precondition(channels(InlineDiffRenderer.lineTint(for: kind), style).a == 0)
    precondition(channels(InlineDiffRenderer.barColor(for: kind), style).a == 0)
  }
}

print("PASS: inline diff model, hunks, emphasis, layout height, scroll axes, blue/red tint scale")
