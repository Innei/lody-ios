import Foundation
import Loro

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let doc = LoroDoc()
_ = try doc.import(bytes: Data(contentsOf: input))
let before = doc.oplogVv()
let history = doc.getList(id: "history")
precondition(history.len() == 1, "JS history must survive native import")
let entry = try history.pushContainer(child: LoroMap())
for (key, value) in ["id": "native-turn", "role": "user", "userId": "fixture-user", "timestamp": "2026-09-18T00:00:00Z", "status": "pending"] {
  try entry.insert(key: key, v: value)
}
try entry.insert(key: "read", v: false)
try entry.insert(key: "finished", v: true)
try entry.insert(key: "fileDiff", v: LoroValue.list(value: []))
let items = try entry.insertContainer(key: "items", child: LoroList())
let item = try items.pushContainer(child: LoroMap())
try item.insert(key: "type", v: "text")
let text = try item.insertContainer(key: "text", child: LoroText())
try text.insert(pos: 0, s: "Native 分享 👋")
let config = try entry.insertContainer(key: "inputConfig", child: LoroMap())
try config.insert(key: "cliType", v: "builtin")
try config.insert(key: "agentType", v: "grok")
try config.insert(key: "prompt", v: "Native 分享 👋")
doc.commit()
try doc.export(mode: .updates(from: before)).write(to: output)
print("Native Loro imported JS history and exported an incremental user turn")
