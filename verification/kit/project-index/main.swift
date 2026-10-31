import UIKit

var lody = InboxProjectChip(id: "states:lody-ios", title: "lody-ios")
lody.monogram = "l"
lody.state = .failed
lody.count = 1
var cloud = InboxProjectChip(id: "states:lody-cloud", title: "lody-cloud")
cloud.image = "https://avatars.githubusercontent.com/lody?size=96"
cloud.state = .live
cloud.count = 1
var chat = InboxProjectChip(id: "chat", title: "Chat")
chat.symbol = "bubble.left"
let items = InboxProjectIndexModel.items(sectionIds: ["pinned", "states:lody-cloud", "empty", "states:lody-ios", "chat"], chips: [lody, cloud, chat])
precondition(items.map(\.id) == ["pinned", "states:lody-cloud", "states:lody-ios", "chat"], "Index items follow the list, skipping empty projects: \(items.map(\.id))")
precondition(items[0].symbol == "pin.fill" && items[0].dot == nil, "Pinned uses the pin glyph")
precondition(items[1].image == cloud.image && items[1].dot == .live, "A live project carries a live dot")
precondition(items[2].monogram == "l" && items[2].dot == .failed, "A failed project carries an attention dot")
precondition(items[3].symbol == "bubble.left" && items[3].dot == nil)
precondition(InboxProjectIndexModel.items(sectionIds: ["states:lody-ios"], chips: [lody]).count == 1)

precondition(InboxProjectIndexModel.pitch(count: 4, available: 400) == 44, "Items keep 44 pt when they fit")
precondition(abs(InboxProjectIndexModel.pitch(count: 20, available: 400) - 20) < 0.001, "Too many items pack into the available height")
precondition(InboxProjectIndexModel.pitch(count: 0, available: 400) == 44)

precondition(InboxProjectIndexModel.item(at: -10, count: 4, pitch: 44) == 0, "Scrubbing above the index clamps to the first item")
precondition(InboxProjectIndexModel.item(at: 50, count: 4, pitch: 44) == 1)
precondition(InboxProjectIndexModel.item(at: 900, count: 4, pitch: 44) == 3, "Scrubbing below clamps to the last item")

let tops: [(id: String, y: CGFloat)] = [("pinned", -300), ("states:lody-cloud", -40), ("states:lody-ios", 180)]
precondition(InboxProjectIndexModel.current(tops, edge: 0) == "states:lody-cloud", "The current section is the last band at or above the edge")
precondition(InboxProjectIndexModel.current(tops, edge: 180) == "states:lody-ios", "A band exactly under the edge is current")
precondition(InboxProjectIndexModel.current([("pinned", 50)], edge: 0) == "pinned", "Before any band reaches the edge, the first is current")
precondition(InboxProjectIndexModel.current([], edge: 0) == nil)
var visibility = InboxIndexVisibility()
visibility.setEnabled(true)
visibility.scrollBegan()
precondition(visibility.shown, "Scrolling shows the index")
precondition(visibility.scrollEnded(), "Stopping schedules the hide")
visibility.scrollBegan()
visibility.hideFired()
precondition(visibility.shown, "A hide scheduled before a new scroll must not fire during it")
_ = visibility.scrollEnded()
visibility.hideFired()
precondition(!visibility.shown, "The hide fires once scrolling has stopped")

var tapped = InboxIndexVisibility()
tapped.setEnabled(true)
tapped.scrollBegan()
tapped.touchBegan()
precondition(tapped.touchEnded(), "Lifting a finger off the index schedules the hide even while the list was decelerating")
tapped.hideFired()
precondition(!tapped.shown, "A tap during momentum cannot leave the index up")

var disabled = InboxIndexVisibility()
disabled.scrollBegan()
precondition(!disabled.shown, "A disabled index never shows")
disabled.setEnabled(true)
disabled.scrollBegan()
disabled.setEnabled(false)
precondition(!disabled.shown, "Disabling hides the index")
print("PASS: project index items, packing, scrubbing, current section and visibility")
