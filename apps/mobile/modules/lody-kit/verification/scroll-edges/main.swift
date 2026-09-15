import UIKit

let owner = UIViewController()
let firstPage = UIViewController()
let secondPage = UIViewController()
let first = UIScrollView()
let second = UIScrollView()
owner.addChild(firstPage)
owner.addChild(secondPage)
owner.view.addSubview(firstPage.view)
owner.view.addSubview(secondPage.view)
firstPage.view.addSubview(first)
secondPage.view.addSubview(second)

// A child controller's registration alone is not the outer sheet's contract.
LodyScrollEdges.bind(first, to: firstPage)
LodyScrollEdges.bind(first, to: owner)
precondition(owner.contentScrollView(for: .top) === first)
precondition(owner.contentScrollView(for: .bottom) === first)

// Committing a page change publishes the newly visible list to the sheet.
LodyScrollEdges.bind(second, to: secondPage)
LodyScrollEdges.bind(second, to: owner)
LodyScrollEdges.unbind(first, from: owner)
precondition(owner.contentScrollView(for: .top) === second)
precondition(owner.contentScrollView(for: .bottom) === second,
  "Detaching an old page must not clear the current page's scroll owner")

// Unmounting releases the actual registered page, so a composer cannot retain it.
LodyScrollEdges.unbind(second, from: owner)
precondition(owner.contentScrollView(for: .top) !== second)
precondition(owner.contentScrollView(for: .bottom) !== second)
print("Scroll edges: nested-page publication, replacement and guarded cleanup pass")
