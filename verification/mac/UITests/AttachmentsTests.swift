import XCTest

final class AttachmentsTests: LodyMacUITestCase {
  private func pill(_ name: String) -> XCUIElement {
    scene.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
  }

  func testPickDropRemoveAndAFailedSendRestoresTheDraft() {
    open("attachments", "light")
    let input = scene.textViews["composer-input"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    scene.buttons["composer-attach"].click()
    eventually("picked files join the draft") { pill("notes.txt").exists && pill("diagram.png").exists }

    send(["lodymacverify://act/drop?seq=1&field=composer"])
    eventually("a file dropped on the composer joins the draft") { pill("lody-verify-dropped.txt").exists }
    attach("attachments-dropped", scene)

    pill("notes.txt").buttons["Remove"].click()
    eventually("remove drops the file") { !pill("notes.txt").exists }

    input.click()
    input.typeText("Here are the files")
    input.typeKey(.return, modifierFlags: [])
    eventually("a failed send restores the text and the files") {
      value(input) == "Here are the files" && pill("diagram.png").exists && pill("lody-verify-dropped.txt").exists
    }
    attach("attachments-restored", scene)
  }
}

final class TranscriptMediaTests: LodyMacUITestCase {
  func testClickingAnImageOpensQuickLook() {
    open("transcript-media", "light")
    let image = scene.buttons["transcript-image"]
    XCTAssertTrue(image.waitForExistence(timeout: 5))
    image.click()
    let preview = app.windows["Quick Look"].staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "lody-fixture-img-layout")).firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout: 10), "Quick Look shows the image's file")
    attach("transcript-media-quicklook")
    app.typeKey(.escape, modifierFlags: [])
  }
}
