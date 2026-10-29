import Foundation

public struct SessionPermission: Equatable, Sendable {
  public struct Option: Decodable, Equatable, Sendable {
    public let optionId: String
    public let name: String
    public let kind: String?

    public init(optionId: String, name: String, kind: String?) {
      self.optionId = optionId
      self.name = name
      self.kind = kind
    }
  }

  public struct Question: Decodable, Equatable, Sendable {
    public struct Option: Decodable, Equatable, Sendable {
      public let label: String
      public let description: String?
      public let preview: String?

      public init(label: String, description: String?, preview: String?) {
        self.label = label
        self.description = description
        self.preview = preview
      }
    }
    public let id: String?
    public let header: String
    public let question: String
    public let options: [Option]
    public let multiSelect: Bool
    public let allowCustomAnswer: Bool?
    public let isSecret: Bool?

    public init(id: String?, header: String, question: String, options: [Option], multiSelect: Bool, allowCustomAnswer: Bool?, isSecret: Bool?) {
      self.id = id
      self.header = header
      self.question = question
      self.options = options
      self.multiSelect = multiSelect
      self.allowCustomAnswer = allowCustomAnswer
      self.isSecret = isSecret
    }
  }

  public struct Questions: Decodable, Equatable, Sendable {
    public let questions: [Question]
    public let allowCustomAnswer: Bool

    public func key(at index: Int) -> String {
      let question = questions[index]
      let candidates: [(String?, [String?])] = [
        (question.id, questions.map(\.id)),
        (question.question, questions.map(\.question)),
        (question.header, questions.map(\.header)),
      ]
      for (candidate, values) in candidates {
        if let value = candidate, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           values.filter({ $0 == value }).count == 1 { return value }
      }
      return String(index)
    }

    public func allowsText(at index: Int) -> Bool {
      let question = questions[index]
      return question.options.isEmpty || (question.allowCustomAnswer ?? allowCustomAnswer)
    }

    public init(questions: [Question], allowCustomAnswer: Bool) {
      self.questions = questions
      self.allowCustomAnswer = allowCustomAnswer
    }
  }

  public let entryId: String
  public let itemId: String
  public let requestId: String
  public let kind: String
  public let title: String
  public let path: String?
  public let options: [Option]?
  public let questionMeta: Questions?

  // Decode only pending tool requests. Other transcript items keep their own schemas.
  public static func first(in entries: [[String: Any]]) throws -> Self? {
    for entry in entries {
      for item in entry["items"] as? [[String: Any]] ?? [] {
        guard item["type"] as? String == "tool_call",
              let permission = item["permission"] as? [String: Any], permission["pending"] as? Bool == true else { continue }
        return try target(entryId: entry["id"] as? String, item: item, permission: permission)
      }
    }
    return nil
  }

  public static func target(entryId: String?, item: [String: Any], permission: [String: Any]) throws -> Self {
    guard let entryId, let itemId = item["itemId"] as? String,
          let requestId = permission["requestId"] as? String, !requestId.isEmpty,
          let kind = item["kind"] as? String, let title = item["title"] as? String else {
      throw CocoaError(.coderReadCorrupt)
    }
    func decode<T: Decodable>(_ type: T.Type, _ key: String) throws -> T? {
      guard let value = permission[key] else { return nil }
      return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
    let questions = try decode(Questions.self, "questionMeta")
    if let questions, questions.questions.isEmpty { throw CocoaError(.coderReadCorrupt) }
    return Self(
      entryId: entryId, itemId: itemId, requestId: requestId,
      kind: permission["kind"] as? String == "ask_user_question" ? "ask_user_question" : kind,
      title: title, path: item["path"] as? String, options: try decode([Option].self, "options"), questionMeta: questions
    )
  }

  public init(entryId: String, itemId: String, requestId: String, kind: String, title: String, path: String?, options: [Option]?, questionMeta: Questions?) {
    self.entryId = entryId
    self.itemId = itemId
    self.requestId = requestId
    self.kind = kind
    self.title = title
    self.path = path
    self.options = options
    self.questionMeta = questionMeta
  }
}

// Owned by one session controller, so leaving the session naturally releases the gate.
public struct SessionPermissionGate {
  public private(set) var open = false
  public private(set) var dismissed = false
  private var answered: Set<String> = []
  private var presented = false

  public var canPrompt: Bool { !open && !dismissed }

  // The catalog waiting hint can lag an answer; only use it before the first presentation.
  public func shouldOpen(_ requestId: String? = nil) -> Bool {
    canPrompt && (requestId.map { !answered.contains($0) } ?? !presented)
  }

  public mutating func opened() {
    open = true
    presented = true
  }
  public mutating func closed(answer: String? = nil, cancelled: Bool = false) {
    open = false
    dismissed = dismissed || cancelled
    if let answer { answered.insert(answer) }
  }

  public init(open: Bool = false, dismissed: Bool = false) {
    self.open = open
    self.dismissed = dismissed
  }
}
