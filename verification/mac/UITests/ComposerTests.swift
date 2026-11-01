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
        app.buttons["composer-options-reset"].click()
        eventually("new-session reset uses the existing choice persistence") { scene.buttons["composer-model"].label == "Default model, Default" }
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
  func testModelPickerExpandsWithoutChangingItsAnchorSide() {
    for appearance in ["light", "dark"] {
      open("model-picker-reference", appearance)
      let anchor = scene.buttons["composer-model"]
      anchor.click()
      let panel = app.groups["composer-options-panel"]
      XCTAssertTrue(panel.waitForExistence(timeout: 3))
      let compact = panel.frame
      let origin = anchor.frame
      attach("anchor-compact-\(appearance)", panel)
      attach("anchor-compact-desktop-\(appearance)")
      app.buttons["composer-model-list"].click()
      XCTAssertTrue(app.tables["composer-model-choices"].waitForExistence(timeout: 3))
      let expanded = panel.frame
      attach("anchor-expanded-\(appearance)", panel)
      attach("anchor-expanded-desktop-\(appearance)")
      app.buttons["composer-options-back"].click()
      XCTAssertTrue(app.sliders["composer-effort-slider"].waitForExistence(timeout: 3))
      let returned = panel.frame
      attach("anchor-returned-desktop-\(appearance)")
      app.buttons["composer-model-list"].click()
      app.tables["composer-model-choices"].staticTexts["GPT-6.1 Terra"].click()
      let selected = panel.frame
      attach("anchor-selected-desktop-\(appearance)")
      XCTAssertLessThanOrEqual(compact.maxY, origin.minY, "the bottom composer opens its panel above the anchor from the start")
      XCTAssertLessThanOrEqual(expanded.maxY, origin.minY)
      XCTAssertEqual(expanded.maxY, compact.maxY, accuracy: 1, "expanding the model list preserves the same anchored bottom edge")
      XCTAssertEqual(returned.maxY, compact.maxY, accuracy: 1, "Back must not flip the panel below its anchor")
      XCTAssertEqual(selected.maxY, compact.maxY, accuracy: 1, "selecting another model keeps the same anchor side")
      app.typeKey(.escape, modifierFlags: [])
    }
  }

  func testReferenceModelPickerKeepsSelectionSeparateFromHover() {
    for appearance in ["light", "dark"] {
      open("model-picker-reference", appearance)
      XCTAssertEqual(scene.buttons["composer-model"].label, "GPT-6 Astra, Medium")
      scene.buttons["composer-model"].click()
      let panel = app.groups["composer-options-panel"]
      XCTAssertTrue(panel.waitForExistence(timeout: 3))
      attach("reference-effort-\(appearance)", panel)
      attach("reference-effort-desktop-\(appearance)")
      let fast = app.descendants(matching: .any).matching(identifier: "composer-fast").firstMatch
      fast.click()
      XCTAssertEqual((fast.value as? NSNumber)?.intValue, 1)
      fast.click()
      app.buttons["composer-model-list"].click()
      let table = app.tables["composer-model-choices"]
      XCTAssertTrue(table.waitForExistence(timeout: 3))
      XCTAssertTrue(table.staticTexts["Use the agent’s default model"].exists)
      table.staticTexts["GPT-5.6 Sol"].hover()
      XCTAssertEqual(scene.buttons["composer-model"].label, "GPT-6 Astra, Medium", "hover never changes the selected model")
      attach("reference-models-\(appearance)", panel)
      attach("reference-models-desktop-\(appearance)")
      table.typeKey(.downArrow, modifierFlags: [])
      table.typeKey(.return, modifierFlags: [])
      eventually("keyboard confirmation applies the model and clears its old effort") {
        scene.buttons["composer-model"].label == "GPT-6.1 Terra, Default"
      }
      app.sliders["composer-effort-slider"].adjust(toNormalizedSliderPosition: 1)
      eventually("the native slider changes the current model's effort") {
        scene.buttons["composer-model"].label == "GPT-6.1 Terra, Extra High"
      }
      fast.click()
      XCTAssertEqual((fast.value as? NSNumber)?.intValue, 1)
      app.buttons["composer-options-reset"].click()
      XCTAssertEqual((fast.value as? NSNumber)?.intValue, 0, "reply reset persists Fast through the real host callback")
      XCTAssertEqual(scene.buttons["composer-model"].label, "Default model, Default")
      XCTAssertFalse(app.buttons["composer-options-reset"].isEnabled, "reset is unavailable when already using agent defaults")
      app.buttons["composer-model-list"].click()
      app.buttons["composer-options-back"].click()
      XCTAssertEqual(scene.buttons["composer-model"].label, "Default model, Default", "Back preserves the choice")
      app.typeKey(.escape, modifierFlags: [])
      eventually("Escape closes the single transient popover") { !panel.exists }
    }
  }

  func testModelPickerDesignStudies() {
    for appearance in ["light", "dark"] {
      for variant in ["a", "b", "c"] {
        open("model-picker-\(variant)", appearance)
        scene.buttons["composer-model"].click()
        let panel = app.groups["model-study-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        attach("model-study-\(variant)-\(appearance)", scene)
        attach("model-study-\(variant)-panel-\(appearance)", panel)
        attach("model-study-\(variant)-desktop-\(appearance)")
        if variant == "b" {
          app.buttons["model-study-heading"].click()
          XCTAssertTrue(app.tables["model-study-choices"].waitForExistence(timeout: 3))
          attach("model-study-b-list-\(appearance)", scene)
          attach("model-study-b-list-panel-\(appearance)", panel)
          attach("model-study-b-list-desktop-\(appearance)")
        }
        if variant == "c" {
          app.popUpButtons["model-study-popup"].click()
          XCTAssertTrue(app.menuItems["Sonnet 5.5"].waitForExistence(timeout: 3))
          attach("model-study-c-menu-\(appearance)", scene)
          attach("model-study-c-menu-desktop-\(appearance)")
          app.menuItems["Sonnet 5.5"].click()
        } else {
          app.tables["model-study-choices"].staticTexts["Sonnet 5.5"].click()
        }
        eventually("each alternative applies the model and clears its old effort") {
          scene.buttons["composer-model"].label == "Sonnet 5.5, Default"
        }
        app.sliders["model-study-effort"].adjust(toNormalizedSliderPosition: 1)
        eventually("effort is restricted to the chosen model") {
          scene.buttons["composer-model"].label == "Sonnet 5.5, High"
        }
        app.typeKey(.escape, modifierFlags: [])
        eventually("the study remains a dismissible native popover") { !panel.exists }
      }
    }
  }

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

  func testPermissionInterruptionDesignStudies() {
    for appearance in ["light", "dark"] {
      open("permission-study-a", appearance)
      let next = scene.buttons["permission-study-allow"]
      XCTAssertTrue(next.waitForExistence(timeout: 3))
      XCTAssertFalse(scene.textViews["composer-input"].isEnabled)
      XCTAssertFalse(next.isEnabled, "permission needs an explicit choice")
      attach("permission-glass-empty-\(appearance)", scene)
      let allow = scene.radioButtons["permission-study-option-0"]
      XCTAssertTrue(allow.exists, "options use native radio controls")
      allow.click()
      eventually("choosing an answer enables Continue") { next.isEnabled }
      attach("permission-study-a-\(appearance)", scene)
      next.click()
      eventually("the preserved draft returns") { scene.textViews["composer-input"].isEnabled }
      XCTAssertEqual(value(scene.textViews["composer-input"]), "Keep the native controls and align the sidebar rows.")
      attach("permission-glass-restored-\(appearance)", scene)

      open("permission-question-glass", appearance)
      XCTAssertTrue(scene.radioButtons["permission-study-option-0"].waitForExistence(timeout: 3))
      scene.radioButtons["permission-study-option-0"].click()
      attach("question-glass-selected-\(appearance)", scene)
      scene.buttons["permission-study-allow"].click()
      let custom = scene.textFields["permission-study-custom"]
      XCTAssertTrue(custom.waitForExistence(timeout: 3))
      custom.click()
      custom.typeText("Keep activity visible only for running sessions.")
      attach("question-glass-custom-\(appearance)", scene)
      scene.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Question 1")).firstMatch.click()
      XCTAssertEqual((scene.radioButtons["permission-study-option-0"].value as? NSNumber)?.intValue, 1, "changing question preserves the answer")
      scene.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Question 2")).firstMatch.click()
      XCTAssertEqual(value(scene.textFields["permission-study-custom"]), "Keep activity visible only for running sessions.")
      scene.buttons["permission-study-allow"].click()
      eventually("answering restores the editor") { scene.textViews["composer-input"].isEnabled }
      XCTAssertEqual(value(scene.textViews["composer-input"]), "Keep the native controls and align the sidebar rows.")
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
