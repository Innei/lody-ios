import Foundation
import LodyCore
import LodyData

enum MacQuestionAction {
  case select(Int), text(String), page(Int), submit
}

struct MacQuestionDraft: Equatable {
  struct Answer: Equatable {
    var selected: Set<Int> = []
    var text = ""
  }

  let meta: SessionPermission.Questions
  private(set) var page = 0
  private(set) var drafts: [Answer]
  var current: Answer { drafts[page] }

  init(meta: SessionPermission.Questions) {
    self.meta = meta
    drafts = meta.questions.map { _ in Answer() }
  }

  mutating func select(_ index: Int) {
    let question = meta.questions[page]
    guard question.options.indices.contains(index) else { return }
    drafts[page].text = ""
    if question.multiSelect {
      if !drafts[page].selected.insert(index).inserted { drafts[page].selected.remove(index) }
    } else { drafts[page].selected = [index] }
  }

  mutating func setText(_ text: String) {
    guard meta.allowsText(at: page) else { return }
    drafts[page].text = text
    if !text.isEmpty { drafts[page].selected = [] }
  }

  mutating func setPage(_ index: Int) {
    guard meta.questions.indices.contains(index) else { return }
    page = index
  }

  var answers: [String: RuntimeContract.JSONValue]? {
    var result: [String: RuntimeContract.JSONValue] = [:]
    for (index, draft) in drafts.enumerated() {
      let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let labels = draft.selected.sorted().map { meta.questions[index].options[$0].label }
      if !text.isEmpty, meta.allowsText(at: index) { result[meta.key(at: index)] = .string(text) }
      else if !labels.isEmpty, meta.questions[index].multiSelect { result[meta.key(at: index)] = .array(labels.map { .string($0) }) }
      else if let label = labels.first { result[meta.key(at: index)] = .string(label) }
      else { return nil }
    }
    return result.isEmpty ? nil : result
  }
}
