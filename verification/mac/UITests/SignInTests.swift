import AppKit
import XCTest

final class SignInTests: LodyMacUITestCase {
  func testDeviceCodeSignInStartsCopiesAndCancels() {
    for appearance in ["light", "dark"] {
      open("sign-in", appearance)
      XCTAssertTrue(scene.staticTexts["Welcome to Lody"].waitForExistence(timeout: 5))
      XCTAssertTrue(scene.buttons["Continue in Browser"].isEnabled)
      XCTAssertFalse(scene.staticTexts["WXYZ-1234"].exists, "no device code before sign-in starts")
      attach("sign-in-\(appearance)", scene)
    }
    scene.buttons["Continue in Browser"].click()
    XCTAssertTrue(scene.staticTexts["WXYZ-1234"].waitForExistence(timeout: 5), "the device code appears")
    XCTAssertTrue(scene.staticTexts["Confirm in Your Browser"].exists)
    XCTAssertTrue(scene.buttons["Open Browser Again"].exists, "the primary button reopens the browser")
    NSPasteboard.general.clearContents()
    scene.buttons["Copy Code"].click()
    eventually("the copy button puts the code on the pasteboard") { NSPasteboard.general.string(forType: .string) == "WXYZ-1234" }
    attach("sign-in-code-dark", scene)
    scene.buttons["Cancel"].click()
    eventually("cancelling clears the device code") { !scene.staticTexts["WXYZ-1234"].exists }
  }

  func testSignedInStateNamesTheUser() {
    open("sign-in-done", "dark")
    XCTAssertTrue(scene.staticTexts["Signed in as Innei"].waitForExistence(timeout: 5))
    attach("sign-in-done-dark", scene)
  }
}
