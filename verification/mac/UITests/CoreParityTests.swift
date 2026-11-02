import XCTest

final class CoreParityTests: LodyMacUITestCase {
  func testQuestionsQueueSteeringAndSinglePrimaryActionMatchIOS() {
    for appearance in ["light", "dark"] {
      open("core-parity", appearance)
      XCTAssertTrue(scene.buttons["question-next"].waitForExistence(timeout: 5))
      XCTAssertFalse(scene.buttons["composer-send"].exists)
      XCTAssertFalse(scene.buttons["composer-stop"].exists)
      attach("core-questions-\(appearance)", scene)
      scene.checkBoxes["question-option-0"].click()
      scene.checkBoxes["question-option-1"].click()
      scene.buttons["question-next"].click()
      let custom = scene.textFields["question-custom"]
      custom.click()
      custom.typeText("Run the focused native checks")
      scene.buttons["question-submit"].click()
      eventually("answering restores the composer") { scene.buttons["composer-stop"].exists }
      XCTAssertFalse(scene.buttons["composer-send"].exists)
      XCTAssertFalse(scene.buttons["composer-queue"].exists)
      XCTAssertFalse(scene.buttons["composer-changes"].exists)
      XCTAssertEqual(scene.sheets.count, 0)
      let first = scene.buttons["queue-message-0"]
      XCTAssertTrue(first.waitForExistence(timeout: 5))
      attach("core-queue-\(appearance)", scene)
      first.click()
      let editor = scene.textViews["queue-editor"]
      XCTAssertTrue(editor.waitForExistence(timeout: 5))
      editor.click()
      editor.typeKey("a", modifierFlags: .command)
      editor.typeText("Add arrow-key navigation")
      attach("core-queue-edit-\(appearance)", scene)
      scene.buttons["queue-save"].click()
      eventually("queue text saves with its attachment") { scene.buttons["queue-message-0"].label.contains("Add arrow-key navigation") }
      scene.buttons["queue-message-0"].rightClick()
      app.menuItems["Move down"].click()
      eventually("native context menu reorders the message") { scene.buttons["queue-message-1"].label.contains("Add arrow-key navigation") }
      scene.buttons["queue-message-2"].rightClick()
      app.menuItems["Remove"].click()
      eventually("remove only deletes the chosen item") { !scene.buttons["queue-message-2"].exists }
      scene.buttons["queue-steer-0"].click()
      eventually("the remaining queued message stays above the composer") { scene.buttons["queue-message-0"].label.contains("Add arrow-key navigation") }
      let input = scene.textViews["composer-input"]
      input.click()
      input.typeText("Guide the running task")
      eventually("typing changes the same action from stop to send") { scene.buttons["composer-send"].exists && !scene.buttons["composer-stop"].exists }
      attach("core-single-action-\(appearance)", scene)
      input.typeKey("a", modifierFlags: .command)
      input.typeKey(.delete, modifierFlags: [])
      eventually("clearing the input returns to stop") { scene.buttons["composer-stop"].exists }
      scene.buttons["composer-stop"].click()
      eventually("stopping returns to idle send") { !scene.buttons["composer-stop"].exists }
      XCTAssertTrue(scene.buttons["transcript-changes"].exists)
      XCTAssertEqual(scene.sheets.count, 0)
      attach("core-stopped-\(appearance)", scene)
    }
  }
}

final class CoreDraftTests: LodyMacUITestCase {
  func testTextAndAttachmentsSurviveSwitchingAndRecreatingTheComposer() {
    for appearance in ["light", "dark"] {
      open("core-draft", appearance)
      let input = scene.textViews["composer-input"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      input.click()
      input.typeText("Keep this draft and both attachments")
      scene.buttons["composer-attach"].click()
      eventually("both selected files join the draft") { attachment("notes.txt").exists && attachment("diagram.png").exists }
      scene.buttons["Another session"].click()
      eventually("the other conversation has a separate draft") { value(scene.textViews["composer-input"]).isEmpty && !attachment("notes.txt").exists }
      scene.buttons["Draft session"].click()
      eventually("the original draft restores") { value(scene.textViews["composer-input"]) == "Keep this draft and both attachments" && attachment("notes.txt").exists }
      scene.buttons["Reopen composer"].click()
      eventually("recreating the controller restores text and files together") { value(scene.textViews["composer-input"]) == "Keep this draft and both attachments" && attachment("notes.txt").exists && attachment("diagram.png").exists }
      attach("core-draft-restored-\(appearance)", scene)
    }
  }

  private func attachment(_ name: String) -> XCUIElement {
    scene.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
  }
}
