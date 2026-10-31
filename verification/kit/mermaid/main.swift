import UIKit

let script = URL(fileURLWithPath: CommandLine.arguments[1])
let flowchart = "graph TD\n    A[Start] --> B{Ready?}\n    B -->|Yes| C[Done]\n    B -->|No| A"

func ink(_ image: UIImage, rows: Range<Double>, dark: Bool) -> Int {
  let cg = image.cgImage!
  let width = cg.width, height = cg.height
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
  var count = 0
  for y in Int(Double(height) * rows.lowerBound)..<Int(Double(height) * rows.upperBound) {
    for x in 0..<width {
      let red = pixels[(y * width + x) * 4]
      if dark ? red < 96 : red > 160 { count += 1 }
    }
  }
  return count
}

@MainActor
func check() throws {
  let engine = MermaidEngine(script: script)

  guard case let .diagram(svg, size) = engine.layout(flowchart) else { preconditionFailure("A flowchart must lay out") }
  precondition(svg.hasPrefix("<svg") && size.width > 0 && size.height > 0, "\(size)")

  let types = [
    "sequenceDiagram\n    participant App\n    participant Cloud\n    App->>Cloud: Send\n    Cloud-->>App: Reply",
    "stateDiagram-v2\n    [*] --> Idle\n    Idle --> Running: Send\n    Running --> Idle: Done",
    "classDiagram\n    class Session {\n        +String title\n        +send()\n    }",
    "erDiagram\n    PROJECT ||--o{ SESSION : contains",
    "xychart-beta\n    x-axis [Mon, Tue, Wed]\n    y-axis \"Turns\" 0 --> 10\n    bar [2, 5, 8]",
    "pie\n    \"One\" : 1\n    \"Two\" : 2",
    "gantt\n    dateFormat YYYY-MM-DD\n    section Build\n    Port :2026-11-01, 2d",
    "mindmap\n  root((Lody))\n    iOS\n    Mac",
    "graph TD\n    A[开始] --> B[结束]",
  ]
  for source in types {
    guard case .diagram = engine.layout(source) else { preconditionFailure("Pele must lay out: \(source)") }
  }

  guard case let .failed(reason) = engine.layout("graph TD\n    A[Start] --> B{Ready?\n    B -->|Yes| C[Done]") else {
    preconditionFailure("A syntax error must fail")
  }
  precondition(reason.hasPrefix("Parse error on line 3"), reason)
  precondition(!reason.contains("\n") && !reason.hasPrefix("PeleError"), reason)

  guard case .failed = engine.layout("graph TD\n" + String(repeating: "%% retained source\n", count: 129)) else {
    preconditionFailure("Oversized sources must fail before Pele parses them")
  }

  let light = try MermaidRaster.image(svg: svg, size: size, background: "#ffffff", foreground: "#000000", scale: 2)
  precondition(light.size == size && light.scale == 2, "\(light.size) \(light.scale)")
  let dark = try MermaidRaster.image(svg: svg, size: size, background: "#000000", foreground: "#ffffff", scale: 2)
  precondition(ink(light, rows: 0..<0.2, dark: true) > 50, "Light diagram has no ink at the top")
  precondition(ink(dark, rows: 0..<0.2, dark: false) > 50, "Dark diagram has no light ink at the top")
  precondition(ink(light, rows: 0..<1, dark: false) > ink(light, rows: 0..<1, dark: true), "Light diagram background must stay light")

  let squareSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\"><rect x=\"0\" y=\"0\" width=\"100\" height=\"50\" fill=\"#000\"/></svg>"
  let square = try MermaidRaster.image(svg: squareSVG, size: CGSize(width: 100, height: 100), background: "#ffffff", foreground: "#000000", scale: 1)
  precondition(ink(square, rows: 0..<0.45, dark: true) > 4000 && ink(square, rows: 0.55..<1, dark: true) == 0, "CoreSVG output must keep SVG's top-left origin")
}

MainActor.assumeIsolated {
  do { try check() } catch { preconditionFailure("\(error)") }
}
print("PASS: Pele lays out nine diagram types, reports parse errors, bounds input and rasterizes upright in both themes")
