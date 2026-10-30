import AppKit
import SwiftUI

struct MacSettingsRowHighlight: ViewModifier {
  let selected: Bool

  func body(content: Content) -> some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        if selected {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            .padding(.horizontal, -8)
            .padding(.vertical, -2)
        }
      }
  }
}

// SwiftUI's sidebar List always paints an accent-filled selection when it has
// focus; the spec wants the main sidebar's unemphasized grey, so the backing
// table stops highlighting and each row draws its own grey background.
struct MacSidebarHighlightProbe: NSViewRepresentable {
  func makeNSView(context: Context) -> Probe { Probe() }

  func updateNSView(_ view: Probe, context: Context) {
    DispatchQueue.main.async { view.apply() }
  }

  final class Probe: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    func apply() {
      var ancestor = superview
      while let view = ancestor {
        if let table = Self.table(in: view) {
          table.selectionHighlightStyle = .none
          return
        }
        ancestor = view.superview
      }
    }

    private static func table(in view: NSView) -> NSTableView? {
      if let table = view as? NSTableView { return table }
      for child in view.subviews {
        if let table = table(in: child) { return table }
      }
      return nil
    }
  }
}
