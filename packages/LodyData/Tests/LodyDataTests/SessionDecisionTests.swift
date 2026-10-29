import XCTest
import LodyCore
import LodyData

@MainActor
final class SessionDecisionTests: XCTestCase {
  private func plan(_ overrides: [String: Any] = [:]) -> [String: Any] {
    let item: [String: Any] = [
      "type": "proposed_plan", "itemId": "plan", "turnId": "turn", "status": "completed", "isLatest": true, "markdown": "# Plan",
    ]
    return ["id": "answer", "role": "assistant", "items": [item.merging(overrides) { $1 }]]
  }

  func testOnlyTheLatestCompletedPlanIsActionable() {
    XCTAssertEqual(SessionTranscriptFacts.latestProposedPlan([plan()]),
      SessionItemTarget(entryId: "answer", itemId: "plan", detail: "turn"))
    XCTAssertNil(SessionTranscriptFacts.latestProposedPlan([plan(), plan(["status": "delta"])]))
    XCTAssertNil(SessionTranscriptFacts.latestProposedPlan([plan(), ["id": "user", "role": "user", "items": []]]))
  }

  func testFailedRetryExplainsItselfWithLocalizedCopy() async {
    let decision = SessionDecision(.retry)
    let target = SessionItemTarget(entryId: "failure", itemId: "error", detail: "")
    await decision.decide(target: target, enabled: true, entryId: "failure", itemId: "error", id: "send") { _, _ in
      #"{"state":"not_sent"}"#
    }
    let message = decision.state(target: target, enabled: true, answered: [])["message"] as? String
    XCTAssertEqual(message, String(localized: "native.chat.error.retryFailed", bundle: .lodyData))
    XCTAssertNotEqual(message, "native.chat.error.retryFailed")
  }
}
