import XCTest

final class SignInTests: LodyMacUITestCase {
  func testDeviceCodeSignInStartsAndCancels() {
    for appearance in ["light", "dark"] {
      open("sign-in", appearance)
      XCTAssertTrue(scene.staticTexts["Sign in to Lody"].waitForExistence(timeout: 5))
      XCTAssertTrue(scene.buttons["Sign In with Browser"].isEnabled)
      XCTAssertFalse(scene.staticTexts["WXYZ-1234"].exists, "no device code before sign-in starts")
      attach("sign-in-\(appearance)", scene)
    }
    scene.buttons["Sign In with Browser"].click()
    XCTAssertTrue(scene.staticTexts["WXYZ-1234"].waitForExistence(timeout: 5), "the device code appears")
    XCTAssertTrue(scene.buttons["Open Browser Again"].exists, "the primary button reopens the browser")
    attach("sign-in-code-dark", scene)
    scene.buttons["Cancel"].click()
    eventually("cancelling clears the device code") { !scene.staticTexts["WXYZ-1234"].exists }
  }
}
