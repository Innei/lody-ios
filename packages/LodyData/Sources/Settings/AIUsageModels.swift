import Foundation

public enum UsageRange: String, Codable, CaseIterable, Sendable {
  case day, week, month, total
}

public enum UsageSource: String, Codable, Sendable {
  case summary, timeline
}

public struct UsageBreakdown: Codable, Equatable, Sendable {
  public var inputTokens: Double?
  public var outputTokens: Double?
  public var cacheReadInputTokens: Double?
  public var cacheCreationInputTokens: Double?
  public var reasoningOutputTokens: Double?

  public static let keys = ["inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens", "reasoningOutputTokens"]

  public subscript(key: String) -> Double? {
    switch key {
    case "inputTokens": inputTokens
    case "outputTokens": outputTokens
    case "cacheReadInputTokens": cacheReadInputTokens
    case "cacheCreationInputTokens": cacheCreationInputTokens
    case "reasoningOutputTokens": reasoningOutputTokens
    default: nil
    }
  }

  public init(inputTokens: Double? = nil, outputTokens: Double? = nil, cacheReadInputTokens: Double? = nil, cacheCreationInputTokens: Double? = nil, reasoningOutputTokens: Double? = nil) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cacheReadInputTokens = cacheReadInputTokens
    self.cacheCreationInputTokens = cacheCreationInputTokens
    self.reasoningOutputTokens = reasoningOutputTokens
  }
}

public struct UsageTotals: Codable, Equatable, Sendable {
  public var tokens: Double
  public var costUSD: Double?
  public var breakdown: UsageBreakdown?

  public init(tokens: Double, costUSD: Double? = nil, breakdown: UsageBreakdown? = nil) {
    self.tokens = tokens
    self.costUSD = costUSD
    self.breakdown = breakdown
  }
}

public struct UsageBucket: Codable, Equatable, Sendable {
  public var bucketStartMs: Double
  public var tokens: Double
  public var costUSD: Double?

  public init(bucketStartMs: Double, tokens: Double, costUSD: Double? = nil) {
    self.bucketStartMs = bucketStartMs
    self.tokens = tokens
    self.costUSD = costUSD
  }
}

public struct UsageSummary: Codable, Equatable, Sendable {
  public var totals: UsageTotals

  public init(totals: UsageTotals) {
    self.totals = totals
  }
}

public struct UsageTimeline: Codable, Equatable, Sendable {
  public var totals: UsageTotals
  public var startMs: Double
  public var endMs: Double
  public var bucketSizeMs: Double
  public var buckets: [UsageBucket]

  public init(totals: UsageTotals, startMs: Double, endMs: Double, bucketSizeMs: Double, buckets: [UsageBucket]) {
    self.totals = totals
    self.startMs = startMs
    self.endMs = endMs
    self.bucketSizeMs = bucketSizeMs
    self.buckets = buckets
  }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
  public var workspaceId: String
  public var range: UsageRange
  public var retrievedAt: Double
  public var summary: UsageSummary?
  public var timeline: UsageTimeline?
  public var errors: [UsageSource]

  public var valid: Bool {
    let totals = [summary?.totals, timeline?.totals].compactMap { $0 }
    let counts = totals.flatMap { total in
      [total.tokens] + UsageBreakdown.keys.compactMap { total.breakdown?[$0] }
    }
    let fees = totals.compactMap(\.costUSD) + (timeline?.buckets.compactMap(\.costUSD) ?? [])
    let dates = [retrievedAt] + (timeline.map { [$0.startMs, $0.endMs] + $0.buckets.map(\.bucketStartMs) } ?? [])
    let all = counts + (timeline.map { [$0.bucketSizeMs] + $0.buckets.map(\.tokens) } ?? []) + dates
    return !workspaceId.isEmpty
      && (timeline?.buckets.count ?? 0) <= 10000
      && all.allSatisfy { Self.count($0) }
      && dates.allSatisfy { $0 <= 8_640_000_000_000_000 }
      && fees.allSatisfy { $0.isFinite && $0 >= 0 }
  }

  private static func count(_ value: Double) -> Bool {
    value.isFinite && value >= 0 && value <= 9_007_199_254_740_991 && value.rounded() == value
  }

  public init(workspaceId: String, range: UsageRange, retrievedAt: Double, summary: UsageSummary? = nil, timeline: UsageTimeline? = nil, errors: [UsageSource]) {
    self.workspaceId = workspaceId
    self.range = range
    self.retrievedAt = retrievedAt
    self.summary = summary
    self.timeline = timeline
    self.errors = errors
  }
}

public struct UsageRequest: Encodable, Equatable, Sendable {
  public var page = "usage"
  public var action = "list"
  public var workspaceId: String
  public var range: UsageRange

  public init(page: String = "usage", action: String = "list", workspaceId: String, range: UsageRange) {
    self.page = page
    self.action = action
    self.workspaceId = workspaceId
    self.range = range
  }
}

public typealias UsageService = @MainActor (UsageRequest) async throws -> UsageSnapshot
