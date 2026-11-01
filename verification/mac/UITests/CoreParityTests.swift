import XCTest

final class CoreParityTests: LodyMacUITestCase {
  private var sheet: XCUIElement { scene.sheets.firstMatch }

  func testQuestionsQueueSteeringDiffsAndStopUseNativeControls() {
    for appearance in ["light", "dark"] {
      open("core-parity", appearance)
      XCTAssertTrue(scene.buttons["question-submit"].waitForExistence(timeout: 5))
      XCTAssertFalse(scene.buttons["question-submit"].isEnabled)
      attach("core-questions-\(appearance)", scene)
      scene.checkBoxes["question-option-0"].click()
      scene.checkBoxes["question-option-1"].click()
      scene.radioGroups["question-pages"].radioButtons["Notes"].click()
      let custom = scene.textFields["question-custom"]
      custom.click()
      custom.typeText("Run the focused native checks")
      scene.buttons["question-submit"].click()
      eventually("answers remove their request card") { !scene.buttons["question-submit"].exists }
      scene.buttons["composer-queue"].click()
      XCTAssertTrue(sheet.buttons["queue-edit-0"].waitForExistence(timeout: 5))
      sheet.buttons["queue-edit-0"].click()
      let editor = sheet.textViews["queue-editor"]
      XCTAssertTrue(editor.waitForExistence(timeout: 5))
      editor.click()
      editor.typeKey("a", modifierFlags: .command)
      editor.typeText("Add arrow-key navigation")
      attach("core-queue-edit-\(appearance)", scene)
      sheet.buttons["queue-save"].click()
      eventually("queue text saves with the attachment") { sheet.staticTexts["Add arrow-key navigation"].exists && sheet.staticTexts["notes.txt"].exists }
      sheet.buttons["queue-down-0"].click()
      eventually("queue order changes") { value(sheet.staticTexts["queue-message-1"]) == "Add arrow-key navigation" }
      sheet.buttons["queue-remove-2"].click()
      eventually("remove only deletes the selected queued message") { !sheet.staticTexts["queue-message-2"].exists }
      attach("core-queue-\(appearance)", scene)
      sheet.buttons["queue-steer-0"].click()
      eventually("steering consumes the chosen message") { value(sheet.staticTexts["queue-message-0"]) == "Add arrow-key navigation" }
      sheet.buttons["queue-close"].click()
      eventually("queue closes") { !sheet.exists }
      scene.buttons.matching(identifier: "transcript-changes").firstMatch.click()
      XCTAssertTrue(sheet.textViews["diff-patch"].waitForExistence(timeout: 5))
      eventually("actual turn patch loads") { value(sheet.textViews["diff-patch"]).contains("+  return \"Lody for Mac\"") }
      attach("core-turn-diff-\(appearance)", scene)
      sheet.radioGroups["diff-scope"].radioButtons["All changes"].click()
      XCTAssertTrue(sheet.tables["diff-files"].staticTexts["diff-file-1"].waitForExistence(timeout: 5))
      sheet.tables["diff-files"].staticTexts["diff-file-1"].click()
      eventually("a failed diff has visible retry guidance") { value(sheet.staticTexts["diff-status"]).contains("Couldn’t load") }
      sheet.buttons["diff-refresh"].click()
      eventually("retry loads the selected file") { value(sheet.textViews["diff-patch"]).contains("Lody for Mac") }
      attach("core-session-diff-\(appearance)", scene)
      sheet.tables["diff-files"].staticTexts["diff-file-2"].click()
      eventually("binary files have an explicit state") { value(sheet.staticTexts["diff-status"]).contains("binary") }
      attach("core-binary-diff-\(appearance)", scene)
      sheet.buttons["diff-close"].click()
      eventually("diff closes") { !sheet.exists }
      scene.buttons["composer-stop"].click()
      eventually("confirmed stop removes the stop control") { !scene.buttons["composer-stop"].exists }
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
