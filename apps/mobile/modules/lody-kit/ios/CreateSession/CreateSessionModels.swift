import Foundation

// JSON shapes shared with src/models/send.ts and the LocalStore `create:` preferences.

struct CreateProject: Codable, Equatable, Sendable {
  var id: String
  var machineId: String
  var name: String
  var rootPath = ""

  init(id: String, machineId: String, name: String, rootPath: String = "") {
    self.id = id
    self.machineId = machineId
    self.name = name
    self.rootPath = rootPath
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    machineId = try values.decodeIfPresent(String.self, forKey: .machineId) ?? ""
    name = try values.decodeIfPresent(String.self, forKey: .name) ?? id
    rootPath = try values.decodeIfPresent(String.self, forKey: .rootPath) ?? ""
  }
}

struct CreationAgent: Codable, Equatable, Sendable {
  var id: String
  var name: String
  var machineId: String
  var machineName: String
  var cliType: String
  var agentType: String
  var key: String { "\(machineId):\(id)" }
}

enum ConfigValue: Codable, Equatable, Sendable {
  case string(String)
  case bool(Bool)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let flag = try? container.decode(Bool.self) { self = .bool(flag) }
    else { self = .string(try container.decode(String.self)) }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    }
  }
}

struct CapabilityChoice: Codable, Equatable, Sendable {
  var id: String
  var name: String
  var description: String?
}

struct ConfigOption: Codable, Equatable, Sendable {
  var id: String
  var name: String
  var description: String?
  var category: String?
  var type: String
  var currentValue: ConfigValue?
  var options: [CapabilityChoice] = []
}

struct Capability: Codable, Equatable, Sendable {
  var machineId: String
  var cliType: String
  var agentType: String
  var models: [CapabilityChoice] = []
  var modes: [CapabilityChoice] = []
  var reasoningEfforts: [String: [String]] = [:]
  var reasoningEffortConfigId: String?
  var configOptions: [ConfigOption]?
  var steer: Bool?
}

struct CreationOptions: Codable, Equatable, Sendable {
  var sessionId: String
  var project: CreateProject?
  var agents: [CreationAgent]
  var capabilities: [Capability]
}

struct ModelChoice: Codable, Equatable, Sendable {
  var modelId: String?
  var effort: String?
  var modeId: String?
  var configOptionValues: [String: ConfigValue]?
}

struct ProjectPrefs: Codable, Equatable, Sendable {
  var modelId: String?
  var effort: String?
  var modeId: String?
  var configOptionValues: [String: ConfigValue]?
  var machineId: String?
  var agentKey: String?

  var choice: ModelChoice {
    ModelChoice(modelId: modelId, effort: effort, modeId: modeId, configOptionValues: configOptionValues)
  }
}

struct CreatePrefs: Codable, Equatable, Sendable {
  var projectId: String?
  var context: String?
  var projects: [String: ProjectPrefs]?
  var modelChoices: [String: ModelChoice]?
}

enum CreateJSON {
  static func encode<Value: Encodable>(_ value: Value) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { return "null" }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode<Value: Decodable>(_ type: Value.Type, _ text: String) -> Value? {
    try? JSONDecoder().decode(type, from: Data(text.utf8))
  }
}
