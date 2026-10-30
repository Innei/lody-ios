import AppKit

@MainActor
enum MacOnboardingChrome {
  static let size = NSSize(width: 880, height: 560)

  struct Saved {
    let frame: NSRect
    let minSize: NSSize
  }

  @discardableResult
  static func enter(_ window: NSWindow, keeping saved: Saved? = nil) -> Saved {
    let saved = saved ?? Saved(frame: window.frame, minSize: window.minSize)
    window.styleMask.remove(.resizable)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.toolbar?.isVisible = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.minSize = size
    let old = window.frame
    window.setFrame(NSRect(x: (old.midX - size.width / 2).rounded(), y: (old.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height), display: true)
    return saved
  }

  static func leave(_ window: NSWindow, restoring saved: Saved?) {
    window.styleMask.insert(.resizable)
    window.titlebarAppearsTransparent = false
    window.titleVisibility = .visible
    window.toolbar?.isVisible = true
    window.appearance = nil
    window.minSize = saved?.minSize ?? NSSize(width: 760, height: 480)
    if let saved {
      window.setFrame(saved.frame, display: true)
    } else {
      let old = window.frame
      window.setFrame(NSRect(x: old.midX - 550, y: old.midY - 360, width: 1100, height: 720), display: true)
    }
  }
}

enum MacSignInCopy {
  static func minutesLeft(_ seconds: TimeInterval) -> Int? {
    seconds > 0 ? Int((seconds / 60).rounded(.up)) : nil
  }

  static func legalURL(_ page: String, language: String) -> URL {
    let path = language.hasPrefix("zh") ? "/zh/\(page)" : "/\(page)"
    return URL(string: "https://lody.ai\(path)")!
  }

  static var language: String {
    Bundle.lodyMac.preferredLocalizations.first ?? "en"
  }

  static func legalText() -> NSAttributedString {
    let terms = String(localized: "mac.signIn.terms", bundle: .lodyMac)
    let privacy = String(localized: "mac.signIn.privacy", bundle: .lodyMac)
    let text = String(format: String(localized: "mac.signIn.legal", bundle: .lodyMac), terms, privacy)
    let out = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    for (word, page) in [(terms, "terms"), (privacy, "privacy")] {
      let range = (text as NSString).range(of: word)
      if range.location != NSNotFound {
        out.addAttribute(.link, value: legalURL(page, language: language), range: range)
      }
    }
    return out
  }
}
