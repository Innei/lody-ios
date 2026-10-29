import XCTest
import LodyData

final class AuthAPITests: XCTestCase {
  final class Fixture: @unchecked Sendable {
    var now = 0.0
    var waits: [Double] = []
    var requests: [URLRequest] = []
    var replies: [(Any, Int)] = []

    func api() -> AuthAPI {
      var api = AuthAPI()
      api.now = { self.now }
      api.sleep = { milliseconds in
        try Task.checkCancellation()
        self.waits.append(milliseconds)
        self.now += milliseconds
      }
      api.transport = { request in
        self.requests.append(request)
        let (body, status) = self.replies.removeFirst()
        return (try JSONSerialization.data(withJSONObject: body, options: .fragmentsAllowed), status)
      }
      return api
    }
  }

  private let code = DeviceCode(deviceCode: "synthetic", userCode: "CODE", verificationURL: "https://lody.ai/device", expiresIn: 30, interval: 1)

  func testDeviceFlowBacksOffUntilTheTokenArrives() async throws {
    let fixture = Fixture()
    fixture.replies = [(["error": "authorization_pending"], 400), (["error": "slow_down"], 400), (["access_token": "synthetic-token"], 200)]
    let token = try await fixture.api().pollToken(code)
    XCTAssertEqual(token, "synthetic-token")
    XCTAssertEqual(fixture.waits, [1000, 1000, 6000])
    XCTAssertEqual(fixture.requests.first?.url?.absoluteString, "https://backend.lody.ai/api/auth/device/token")
  }

  func testExpiredCodeNeverRequests() async {
    let fixture = Fixture()
    let short = DeviceCode(deviceCode: "synthetic", userCode: "CODE", verificationURL: "", expiresIn: 1, interval: 1)
    do {
      _ = try await fixture.api().pollToken(short)
      XCTFail("expired code must fail")
    } catch {
      XCTAssertEqual((error as? AuthFailure)?.message, String(localized: "auth.error.codeExpired", bundle: .lodyData))
    }
    XCTAssertTrue(fixture.requests.isEmpty)
  }
}
