import UIKit

struct LodyListRow {
  var parent = false
  var imageTint = ""
  var unread = false
}

@MainActor func descendants(_ view: UIView) -> [UIView] {
  view.subviews.flatMap { [$0] + descendants($0) }
}

precondition(ChatFileCell.rowHeight() == 40, "File rows are 40 pt")
precondition(ChatFileCell.headerHeight == 42, "The summary row is 42 pt")

let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
let cell = ChatFileCell(frame: CGRect(x: 16, y: 0, width: 358, height: ChatFileCell.rowHeight()))
window.addSubview(cell)
let path = "Sources/Chat/Transcript.swift"
let pathTitle = ChatFileCell.title(for: path)
precondition(pathTitle.string.hasPrefix("Transcript.swift"), "File rows lead with the file name")
let nameFont = pathTitle.attribute(.font, at: 0, effectiveRange: nil) as! UIFont
let nameWeight = (nameFont.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
precondition(nameWeight >= UIFont.Weight.medium.rawValue - 0.01, "The file name is medium weight")
let directoryAt = (pathTitle.string as NSString).range(of: "Sources/Chat/").location
precondition(directoryAt != NSNotFound, "The directory follows the name")
precondition((pathTitle.attribute(.foregroundColor, at: directoryAt, effectiveRange: nil) as? UIColor) == .lodyTertiary, "The directory is tertiary")
let directoryFont = pathTitle.attribute(.font, at: directoryAt, effectiveRange: nil) as! UIFont
precondition(abs(directoryFont.pointSize - LodyDesign.font(.footnote, size: 11.5, compatibleWith: window.traitCollection).pointSize) < 0.01, "The directory is 11.5 pt")
precondition(ChatFileCell.stat(add: 12, del: 0).string == "+12" && ChatFileCell.stat(add: 0, del: 3).string == "−3"
  && ChatFileCell.stat(add: 18, del: 6).string == "+18 −6", "Counts omit a zero side")
let summaryCounts = UILabel()
summaryCounts.attributedText = ChatFileCell.stat(add: 33, del: 7)
let squaresView = ChatDiffstatView(add: 33, del: 7)
let summaryView = ChatFileCell.summaryAccessory(squares: squaresView, counts: summaryCounts)
summaryView.layoutIfNeeded()
precondition(summaryCounts.frame.minX - squaresView.frame.maxX >= 8, "The diffstat squares and the totals keep an 8 pt gap")
precondition(summaryCounts.frame.width >= summaryCounts.intrinsicContentSize.width - 0.01 && summaryView.bounds.width >= summaryCounts.frame.maxX - 0.01,
  "The totals are not clipped")
precondition(ChatFileCell.diffstat(add: 155, del: 36) == 4 && ChatFileCell.diffstat(add: 0, del: 9) == 0 && ChatFileCell.diffstat(add: 0, del: 0) == 0,
  "The diffstat gives green squares in proportion to additions")

func fileRow(_ id: String, _ kind: String, _ group: String) -> ChatRow {
  var row = ChatRow(id: id, entryID: "e", kind: kind, text: id, actionable: true)
  row.group = group
  return row
}
let block = [fileRow("h", "changesHeader", "first"), fileRow("a", "changes", "middle"), fileRow("b", "changes", "last"), fileRow("m", "meta", "")]
let collapsed = ChatFileBlock.visible(block, expanded: [], reviewable: true)
precondition(collapsed.map(\.id) == ["h", "m"] && collapsed[0].group == "only", "A collapsed block shows only its summary")
let open = ChatFileBlock.visible(block, expanded: ["e"], reviewable: true)
precondition(open.map(\.id) == ["h", "a", "b", "e:changesReview", "m"], "An expanded block lists its files and ends with Review all changes")
precondition(open.map(\.group) == ["first", "middle", "middle", "last", ""], "Review all changes closes the expanded block")
precondition(open[3].kind == "changesReview" && open[3].actionable, "Review all changes is an action row")
let rootReview = [fileRow("h", "changesHeader", "first"), fileRow("e:changes:review", "changes", "last")]
let reviewIDs = ChatFileBlock.visible(rootReview, expanded: ["e"], reviewable: true).map(\.id)
precondition(Set(reviewIDs).count == reviewIDs.count, "A root file named review must not collide with Review all changes")
let closed = ChatFileBlock.visible(block, expanded: ["e"], reviewable: false)
precondition(closed.map(\.id) == ["h", "a", "b", "m"] && closed[2].group == "last", "Unreviewable sessions end the block at the last file")
let single = [fileRow("only", "changes", "only")]
precondition(ChatFileBlock.visible(single, expanded: [], reviewable: true).map(\.id) == ["only"], "A single file always shows")
cell.contentConfiguration = ChatFileCell.rowContent(for: path)
cell.apply(group: "first", selected: false)
cell.layoutIfNeeded()
let views = descendants(cell)
precondition(!views.contains { ($0 as? UIImageView)?.image != nil }, "File rows must not display a leading image")
let label = views.compactMap { $0 as? UILabel }.first { $0.attributedText?.string == pathTitle.string }!
let font = label.attributedText!.attribute(.font, at: 0, effectiveRange: nil) as! UIFont
precondition(font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace), "File paths must be monospaced")
let expectedSize = LodyDesign.mono(12.5, weight: .medium, compatibleWith: cell.traitCollection).pointSize
precondition(abs(font.pointSize - expectedSize) < 0.01, "File paths must use scaled 12.5 pt type, got \(font.pointSize), expected \(expectedSize)")
let chrome = cell.subviews.first { $0.layer.masksToBounds && $0.layer.cornerCurve == .continuous }!
precondition(chrome.layer.cornerRadius == 12, "The block must have a 12 pt radius")
precondition(chrome.layer.maskedCorners == [.layerMinXMinYCorner, .layerMaxXMinYCorner], "The first row rounds only the top corners")
for style in [UIUserInterfaceStyle.light, .dark] {
  let traits = UITraitCollection(userInterfaceStyle: style)
  precondition(chrome.backgroundColor!.resolvedColor(with: traits) == UIColor.lodyInset.resolvedColor(with: traits), "The block must use the inset fill in each appearance")
}
let separator = descendants(cell).first { $0.frame.height == 0.5 && !$0.isHidden }!
precondition(separator.frame.minX == 14 && separator.frame.maxX == cell.bounds.width - 14, "The hairline must be inset 14 pt on both sides")
precondition(separator.frame.maxY == cell.bounds.height, "The hairline must separate adjacent rows")
precondition(separator.backgroundColor == .lodyLine, "The hairline must use the line token")
cell.apply(group: "middle", selected: false)
precondition(chrome.layer.maskedCorners.isEmpty && !separator.isHidden, "Middle rows must remain square and separated")
cell.apply(group: "last", selected: false)
precondition(chrome.layer.maskedCorners == [.layerMinXMaxYCorner, .layerMaxXMaxYCorner], "The last row rounds only the bottom corners")
precondition(separator.isHidden, "The last row must not draw an outside hairline")
cell.apply(group: "only", selected: false)
precondition(chrome.layer.maskedCorners == [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner], "An isolated row rounds all corners")
precondition(separator.isHidden, "An isolated row must not draw an outside hairline")
cell.apply(group: "last", selected: true)
precondition(chrome.backgroundColor == .lodyInsetSelected, "Selected files must retain their existing selection feedback")
let header = ChatFileCell(frame: CGRect(x: 16, y: 40, width: 358, height: ChatFileCell.headerHeight))
window.addSubview(header)
let headerText = String.localizedStringWithFormat(String(localized: "native.chat.transcript.fileCount", bundle: .lody), 2)
header.contentConfiguration = ChatFileCell.headerContent(for: headerText)
header.apply(group: "first", selected: false)
header.layoutIfNeeded()
let headerLabel = descendants(header).compactMap { $0 as? UILabel }.first { $0.text == headerText }!
let headerFont = headerLabel.font!
let headerWeight = (headerFont.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
precondition(abs(headerFont.pointSize - LodyDesign.font(.subheadline, size: 14, compatibleWith: header.traitCollection).pointSize) < 0.01 && headerWeight >= UIFont.Weight.semibold.rawValue - 0.01, "The header must use scaled 14 pt semibold type")
precondition(headerLabel.textColor == .lodyInk, "The header must use the ink token")
precondition(header.accessories.isEmpty, "The header must have no navigation chevron")
precondition(descendants(header).contains { $0.frame.height == 0.5 && !$0.isHidden }, "The header must separate its title from the first file")
print("Chat files: grouped chrome, row heights, monospaced paths, icon removal and inset hairlines passed")
