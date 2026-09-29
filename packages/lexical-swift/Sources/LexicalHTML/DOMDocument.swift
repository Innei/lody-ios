import Foundation
import libxml2

public final class DOMNode: @unchecked Sendable {
  public let name: String
  public let attributes: [String: String]
  public let text: String
  public internal(set) var children: [DOMNode] = []
  public internal(set) weak var parent: DOMNode?
  private var index = 0
  private lazy var styles: [String: String] = parseStyle(attributes["style"] ?? "")

  init(name: String, attributes: [String: String] = [:], text: String = "") {
    self.name = name
    self.attributes = attributes
    self.text = text
  }

  public var isText: Bool { name == "#text" }
  public var isElement: Bool { !isText }

  public var classList: Set<String> {
    Set((attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
  }

  public func style(_ property: String) -> String {
    styles[property] ?? ""
  }

  public var textContent: String {
    if isText { return text }
    var output = ""
    var stack: [DOMNode] = [self]
    while let node = stack.popLast() {
      if node.isText { output += node.text }
      stack.append(contentsOf: node.children.reversed())
    }
    return output
  }

  public var firstChild: DOMNode? { children.first }
  public var lastChild: DOMNode? { children.last }

  public var previousSibling: DOMNode? {
    guard let parent, index > 0 else { return nil }
    return parent.children[index - 1]
  }

  public var nextSibling: DOMNode? {
    guard let parent, index + 1 < parent.children.count else { return nil }
    return parent.children[index + 1]
  }

  func append(_ child: DOMNode) {
    child.parent = self
    child.index = children.count
    children.append(child)
  }
}

private func parseStyle(_ value: String) -> [String: String] {
  var styles: [String: String] = [:]
  for declaration in value.split(separator: ";") {
    guard let colon = declaration.firstIndex(of: ":") else { continue }
    let key = declaration[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
    let raw = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    styles[key] = raw.replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces).lowercased()
  }
  return styles
}

public enum DOMDocument {
  static let droppedTags: Set<String> = ["SCRIPT", "STYLE", "HEAD", "TITLE", "IFRAME", "OBJECT", "TEMPLATE", "NOSCRIPT"]
  // libxml2 parses HTML4, where <embed> is not void, so it swallows every following sibling.
  static let unwrappedTags: Set<String> = ["EMBED"]

  public static func parse(html: String) -> DOMNode {
    let body = DOMNode(name: "BODY")
    let bytes = Array(html.utf8)
    guard !bytes.isEmpty else { return body }
    let options = Int32(bitPattern: HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue)
    let document = bytes.withUnsafeBufferPointer { buffer in
      buffer.withMemoryRebound(to: CChar.self) { htmlReadMemory($0.baseAddress, Int32($0.count), nil, "UTF-8", options) }
    }
    guard let document else { return body }
    defer { xmlFreeDoc(document) }
    guard let bodyElement = findBody(xmlDocGetRootElement(document)) else { return body }

    var stack: [(xmlNodePtr?, DOMNode)] = [(bodyElement.pointee.children, body)]
    while let (next, parent) = stack.popLast() {
      guard let node = next else { continue }
      stack.append((node.pointee.next, parent))
      switch node.pointee.type {
      case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
        parent.append(DOMNode(name: "#text", text: node.pointee.content.map { String(cString: $0) } ?? ""))
      case XML_ELEMENT_NODE:
        let tag = String(cString: node.pointee.name).uppercased()
        guard !droppedTags.contains(tag) else { continue }
        if unwrappedTags.contains(tag) {
          stack.append((node.pointee.children, parent))
          continue
        }
        let element = DOMNode(name: tag, attributes: attributes(of: node))
        parent.append(element)
        stack.append((node.pointee.children, element))
      default:
        continue
      }
    }
    return body
  }

  private static func findBody(_ root: xmlNodePtr?) -> xmlNodePtr? {
    var child = root?.pointee.children
    while let node = child {
      if node.pointee.type == XML_ELEMENT_NODE, String(cString: node.pointee.name).lowercased() == "body" { return node }
      child = node.pointee.next
    }
    return nil
  }

  private static func attributes(of node: xmlNodePtr) -> [String: String] {
    var result: [String: String] = [:]
    var attribute = node.pointee.properties
    while let current = attribute {
      let name = String(cString: current.pointee.name).lowercased()
      var value = ""
      var part = current.pointee.children
      while let text = part {
        if let content = text.pointee.content { value += String(cString: content) }
        part = text.pointee.next
      }
      result[name] = value
      attribute = current.pointee.next
    }
    return result
  }
}
