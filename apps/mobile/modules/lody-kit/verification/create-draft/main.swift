import Foundation

let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .appendingPathComponent("../../../../tests/fixtures").standardized
let english = try JSONSerialization.jsonObject(
  with: Data(contentsOf: fixtures.appendingPathComponent("../../locales/en.json").standardized)
) as! [String: String]
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("create-draft.json"))) as! [[String: Any]]
let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("create-draft.golden.json"))) as! [String: [String: String]]

for item in cases {
  let name = item["name"] as! String
  let draftData = try JSONSerialization.data(withJSONObject: item["draft"]!)
  let draft = try JSONDecoder().decode(CreateSessionDraft.self, from: draftData)
  let built = CreateDraftRecord(
    draft: draft, payload: item["payload"] as! [String: Any], createdAt: item["createdAt"] as! String,
    text: { english[$0] ?? $0 }
  )
  precondition(built.recordJSON == golden[name]!["record"], "\(name) record differs from JS:\n\(built.recordJSON)")
  precondition(built.createdJSON == golden[name]!["created"], "\(name) created differs from JS:\n\(built.createdJSON)")
  precondition(built.record?.sessionId == draft.sessionId, "\(name) record does not decode for the outbox")
}
print("PASS: CreateDraftRecord matches createDraft.ts byte for byte")
