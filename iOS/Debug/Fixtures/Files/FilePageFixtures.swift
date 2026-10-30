import LodyCore
import UIKit

@MainActor
final class FileFeedbackFixture {
  weak var owner: UIViewController?
  let outcome: String
  init(_ params: [String: Any]) { outcome = params["feedbackOutcome"] as? String ?? "sent" }
  var feedback: PreviewFeedback {
    PreviewFeedback(send: { [self] report in
      guard let owner else { throw PreviewFeedbackError.unavailable }
      try await LodyShell.shared.callback(from: owner, name: "onFeedback", value: report)
      if outcome == "failed" { throw PreviewFeedbackError.failed("send_failed") }
      return PreviewFeedbackResult(rawValue: outcome)!
    }, openSession: {})
  }
}
