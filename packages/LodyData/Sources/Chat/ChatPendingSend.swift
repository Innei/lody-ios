import Foundation

/// Local visual state uses the dispatch ID, so authoritative history takes its place.
public struct ChatAttachmentUploadProgress: Decodable, Equatable, Sendable {
  public let phase: String
  public let percent: Int?

  public init(phase: String, percent: Int?) {
    self.phase = phase
    self.percent = percent
  }
}

public struct ChatPendingSend: Decodable, Sendable {
  public struct Attachment: Decodable, Sendable {
    public let id: String
    public let name: String
    public let uri: String
    public let kind: String

    public init(id: String, name: String, uri: String, kind: String) {
      self.id = id
      self.name = name
      self.uri = uri
      self.kind = kind
    }
  }
  public let id: String
  public let text: String
  public let attachments: [Attachment]
  public let status: String
  public var startedAt: Double? = nil
  public var failed: Bool? = nil
  public var reconnect: Bool? = nil
  public var queue: Bool? = nil
  public var guide: Bool? = nil
  public var phase: String? = nil
  public var uploadProgress: [String: ChatAttachmentUploadProgress]? = nil

  public init(id: String, text: String, attachments: [Attachment], status: String, startedAt: Double? = nil, failed: Bool? = nil, reconnect: Bool? = nil, queue: Bool? = nil, guide: Bool? = nil, phase: String? = nil, uploadProgress: [String: ChatAttachmentUploadProgress]? = nil) {
    self.id = id
    self.text = text
    self.attachments = attachments
    self.status = status
    self.startedAt = startedAt
    self.failed = failed
    self.reconnect = reconnect
    self.queue = queue
    self.guide = guide
    self.phase = phase
    self.uploadProgress = uploadProgress
  }
}
