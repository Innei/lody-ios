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
      if appearance == "light" {
        scene.menuButtons["sidebar-workspace"].click()
        XCTAssertTrue(app.menuItems["Account"].waitForExistence(timeout: 3), "the account capsule opens the native account menu")
        attach("account-b-menu-light", scene)
        app.typeKey(.escape, modifierFlags: [])
        scene.popUpButtons["composer-agent"].click()
        XCTAssertTrue(app.menuItems["Claude Code"].waitForExistence(timeout: 3), "the context gear opens the native agent menu")
        attach("composer-new-agent-menu-light", scene)
        app.typeKey(.escape, modifierFlags: [])
        scene.buttons["composer-model"].click()
        XCTAssertTrue(app.buttons["composer-model-list"].waitForExistence(timeout: 3))
        app.buttons["composer-model-list"].click()
        app.staticTexts["Opus 5.5"].click()
        let effort = app.sliders["composer-effort-slider"]
        XCTAssertTrue(effort.waitForExistence(timeout: 3))
        effort.adjust(toNormalizedSliderPosition: 1)
        eventually("new-session choices use the same popover") { scene.buttons["composer-model"].label.contains("Opus 5.5, Ultra") }
        attach("composer-new-options-light", app.groups["composer-options-panel"])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(scene.buttons["composer-send"].isEnabled, "model selection never sends an empty draft")
      }
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
  func testReplyKeepsTheWritingSurfaceCompactAndSendsWithReturn() {
    for appearance in ["light", "dark"] {
      open("composer-reply", appearance)
      XCTAssertTrue(scene.textViews["composer-input"].waitForExistence(timeout: 5))
      XCTAssertEqual(scene.textViews["composer-input"].placeholderValue, "Reply…")
      XCTAssertFalse(scene.popUpButtons["composer-project"].exists, "replying uses the single writing surface without a context header")
      XCTAssertEqual(value(scene.popUpButtons["composer-mode"]), "Ask first", "permission mode sits on the left")
      XCTAssertFalse(scene.buttons["composer-send"].isEnabled)
      attach("composer-reply-\(appearance)", scene)
    }
    scene.buttons["composer-model"].click()
    XCTAssertTrue(app.sliders["composer-effort-slider"].waitForExistence(timeout: 3))
    attach("composer-options-dark", app.groups["composer-options-panel"])
    app.buttons["composer-model-list"].click()
    XCTAssertTrue(app.tables["composer-model-choices"].waitForExistence(timeout: 3))
    attach("composer-models-dark", app.groups["composer-options-panel"])
    app.staticTexts["Sonnet 5.5"].click()
    eventually("the popover applies the model and resets effort") { scene.buttons["composer-model"].label.contains("Sonnet 5.5, Default") }
    let slider = app.sliders["composer-effort-slider"]
    slider.adjust(toNormalizedSliderPosition: 0.67)
    eventually("the native slider applies effort") { scene.buttons["composer-model"].label.contains("Medium") }
    app.typeKey(.escape, modifierFlags: [])
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

  func testModelPopoverAndHeatSliderInBothAppearances() {
    for appearance in ["light", "dark"] {
      open("composer-reply", appearance)
      scene.buttons["composer-model"].click()
      let slider = app.sliders["composer-effort-slider"]
      XCTAssertTrue(slider.waitForExistence(timeout: 3))
      XCTAssertTrue(app.groups["composer-options-panel"].waitForExistence(timeout: 3), "the native popover exposes its content group")
      attach("composer-options-\(appearance)", app.groups["composer-options-panel"])
      slider.adjust(toNormalizedSliderPosition: 1)
      eventually("Ultra updates the summary") { scene.buttons["composer-model"].label.contains("Ultra") }
      attach("composer-options-ultra-\(appearance)", app.groups["composer-options-panel"])
      app.typeKey(.escape, modifierFlags: [])
      eventually("Escape dismisses the transient popover") { !slider.exists }
      scene.buttons["composer-model"].click()
      XCTAssertTrue(app.sliders["composer-effort-slider"].waitForExistence(timeout: 3))
      XCTAssertTrue(scene.buttons["composer-model"].label.contains("Ultra"), "reopening preserves the chosen effort")
      app.buttons["composer-model-list"].click()
      app.tables["composer-model-choices"].typeKey(.downArrow, modifierFlags: [])
      app.tables["composer-model-choices"].typeKey(.return, modifierFlags: [])
      eventually("the model list also supports keyboard confirmation") { scene.buttons["composer-model"].label.contains("Sonnet 5.5, Default") }
      app.typeKey(.escape, modifierFlags: [])
    }
  }

  func testCodexComposerDraftAndNaturalWrappingInBothAppearances() {
    for appearance in ["light", "dark"] {
      open("composer-reply", appearance)
      let input = scene.textViews["composer-input"]
      XCTAssertTrue(input.waitForExistence(timeout: 5))
      let empty = input.frame.height
      input.click()
      input.typeText(String(repeating: "Keep the native controls and align the sidebar rows. ", count: 8))
      eventually("the editor grows with wrapped text") { input.frame.height > empty + 10 }
      choose("Full access", in: scene.popUpButtons["composer-mode"])
      attach("composer-codex-draft-\(appearance)", scene)
      input.click()
      input.typeKey("a", modifierFlags: .command)
      input.typeKey(.delete, modifierFlags: [])
      eventually("clearing the draft restores the compact height") { value(input).isEmpty && abs(input.frame.height - empty) <= 1 }
    }
  }
}
