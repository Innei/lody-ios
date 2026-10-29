import XCTest
import LodyCore
@testable import LodyData

final class CreateDraftTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../../tests/fixtures").standardized

  func testDraftRecordsMatchTheDesktopGolden() throws {
    let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("create-draft.json"))) as! [[String: Any]]
    let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("create-draft.golden.json"))) as! [String: [String: String]]
    XCTAssertFalse(cases.isEmpty)
    for item in cases {
      let name = item["name"] as! String
      let draft = try JSONDecoder().decode(CreateSessionDraft.self, from: JSONSerialization.data(withJSONObject: item["draft"]!))
      let built = CreateDraftRecord(
        draft: draft, payload: item["payload"] as! [String: Any], createdAt: item["createdAt"] as! String,
        text: { String(localized: String.LocalizationValue($0), bundle: .lodyData) }
      )
      XCTAssertEqual(built.recordJSON, golden[name]?["record"], name)
      XCTAssertEqual(built.createdJSON, golden[name]?["created"], name)
      XCTAssertEqual(built.record?.sessionId, draft.sessionId, name)
    }
  }
}
