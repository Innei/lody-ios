import LodyCore
import UIKit

@MainActor
final class FileDiffPreviewController: UIViewController {
  static let paths = ["docs/superpowers/.diff-check.md", "src/very-long-directory-name/nested/components/another-long-file-name.ts"]
  private let list = LodyGroupedList(frame: .zero)
  private let fixture = FileDiffFixture()

  override func viewDidLoad() {
    super.viewDidLoad()
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    list.forwarded = { [weak self] name, body in
      guard name == "rowPress", let self, let id = body["id"] as? String, let path = Self.paths.first(where: { "diff-preview:changes:\($0)" == id })
      else { return }
      let request = FileDiffRequest(sessionId: "ui-verify-diff", entryId: "diff-preview", path: path)
      LodyShell.shared.push(FileDiffController(request: request, service: fixture.service), title: FilePathText.basename(path), from: self)
    }
    view.addSubview(list)
    var section = LodyListSection()
    section.id = "diff-preview:changes"
    section.header = String.localizedStringWithFormat(String(localized: "changes.fileCount", bundle: .lody), Self.paths.count)
    section.rows = Self.paths.map { path in
      var row = LodyListRow()
      row.id = "diff-preview:changes:\(path)"
      row.title = FilePathText.basename(path)
      row.subtitle = FilePathText.dirname(path)
      row.subtitleMono = true
      row.filePath = path
      row.diff = ["add": 1, "del": 1]
      row.action = true
      row.navigates = true
      row.disclosure = true
      return row
    }
    list.setSections([section])
  }
}
