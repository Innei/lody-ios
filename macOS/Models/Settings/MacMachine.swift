import Foundation
import LodyCore
import LodyData
import Observation

struct MacMachine: Codable, Equatable, Identifiable, Sendable {
  var kind = "machine"
  var id: String
  var name: String
  var detail: String?
  var readOnly: Bool?

  init(id: String, name: String, detail: String?, readOnly: Bool?) {
    self.id = id
    self.name = name
    self.detail = detail
    self.readOnly = readOnly
  }
}

struct MacMachineRow: Equatable, Identifiable {
  let machine: MacMachine
  let status: String
  var id: String { machine.id }
  var name: String { machine.name.isEmpty ? machine.id : machine.name }
  var owned: Bool { machine.readOnly == false }
  var canRename: Bool { owned }
}
