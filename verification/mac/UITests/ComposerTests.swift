import XCTest

final class ComposerNewTests: LodyMacUITestCase {
  func testNewSessionPicksAnOnlineMachineAndBlocksProjectsWithout() {
    for appearance in ["light", "dark"] {
      open("composer-new", appearance)
      XCTAssertTrue(scene.textViews["composer-input"].waitForExistence(timeout: 5))
      eventually("the first online machine is chosen") { value(scene.popUpButtons["composer-machine"]) == "Mac Studio" }
      XCTAssertEqual(value(scene.popUpButtons["composer-project"]), "lody-ios", "the first project is preselected")
      XCTAssertEqual(value(scene.popUpButtons["composer-agent"]), "Claude Code", "its agent is chosen")
      XCTAssertFalse(scene.buttons["composer-send"].isEnabled, "an empty draft cannot send")
      attach("composer-new-\(appearance)", scene)
    }
    let input = scene.textViews["composer-input"]
    let send = scene.buttons["composer-send"]
    input.click()
    input.typeText("Ship the Mac sidebar")
    eventually("a draft can send") { send.isEnabled }

    choose("handbook", in: scene.popUpButtons["composer-project"])
    eventually("a project without machines blocks sending") { !send.isEnabled }
    XCTAssertEqual(value(scene.staticTexts["composer-notice"]), "No machine is online for this project")
    attach("composer-new-blocked-dark", scene)

    choose("lody-ios", in: scene.popUpButtons["composer-project"])
    eventually("an online project sends again") { send.isEnabled }
    input.click()
    input.typeKey(.return, modifierFlags: [])
    eventually("Return starts the session") {
      value(scene.staticTexts["new-session-status"]) == "Starting “Ship the Mac sidebar”…"
    }
  }
}

final class ComposerReplyTests: LodyMacUITestCase {
  func testReplyTrayShowsContextAndSendsWithReturn() {
    for appearance in ["light", "dark"] {
      open("composer-reply", appearance)
      XCTAssertTrue(scene.textViews["composer-input"].waitForExistence(timeout: 5))
      XCTAssertEqual(scene.textViews["composer-input"].placeholderValue, "Reply…")
      XCTAssertEqual(value(scene.staticTexts["composer-context"]), "lody-ios  ·  mac-client  ·  Mac Studio", "the reply tray is read-only context")
      XCTAssertEqual(value(scene.popUpButtons["composer-mode"]), "Ask first", "permission mode sits on the left")
      XCTAssertFalse(scene.buttons["composer-send"].isEnabled)
      attach("composer-reply-\(appearance)", scene)
    }
    choose("Full access", in: scene.popUpButtons["composer-mode"])
    eventually("the mode menu applies") { value(scene.popUpButtons["composer-mode"]) == "Full access" }
    attach("composer-reply-full-access-dark", scene)

    let input = scene.textViews["composer-input"]
    input.click()
    input.typeText("Ship it")
    eventually("a draft can send") { scene.buttons["composer-send"].isEnabled }
    input.typeKey(.return, modifierFlags: [])
    eventually("the reply joins the transcript") { scene.staticTexts["Ship it"].exists }
    eventually("the composer clears") { value(input).isEmpty }
  }
}
