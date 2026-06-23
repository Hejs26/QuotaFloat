import Foundation

enum QuotaProvider: String, Codable, CaseIterable, Identifiable, Sendable {
  case codex
  case claude
  case kimi

  var id: String { self.rawValue }

  var displayName: String {
    self.definition.displayName
  }
}

enum QuotaPaceStatus: String, Equatable, Sendable {
  case roomy = "宽裕"
  case normal = "正常"
  case fast = "偏快"
  case urgent = "告急"
  case exhausted = "耗尽"
}

struct QuotaPaceEvaluation: Equatable, Sendable {
  let status: QuotaPaceStatus
  let idealRemainingPercent: Double
  let deltaPercent: Double
}

struct QuotaWindow: Codable, Equatable, Sendable {
  let usedPercent: Double
  let resetsAt: Date?
  let windowMinutes: Int?

  init(usedPercent: Double, resetsAt: Date?, windowMinutes: Int?) {
    self.usedPercent = min(100, max(0, usedPercent.isFinite ? usedPercent : 0))
    self.resetsAt = resetsAt
    self.windowMinutes = windowMinutes
  }

  var remainingPercent: Double {
    max(0, 100 - self.usedPercent)
  }

  func paceEvaluation(now: Date) -> QuotaPaceEvaluation? {
    if self.remainingPercent == 0 {
      return QuotaPaceEvaluation(
        status: .exhausted,
        idealRemainingPercent: 0,
        deltaPercent: 0)
    }

    guard
      let resetsAt = self.resetsAt,
      let windowMinutes = self.windowMinutes,
      windowMinutes > 0
    else {
      return nil
    }

    let duration = TimeInterval(windowMinutes) * 60
    let secondsRemaining = resetsAt.timeIntervalSince(now)
    guard secondsRemaining > 0, secondsRemaining <= duration else { return nil }

    let idealRemaining = min(100, max(0, secondsRemaining / duration * 100))
    let delta = self.remainingPercent - idealRemaining
    let status: QuotaPaceStatus
    if delta >= 5 {
      status = .roomy
    } else if delta > -5 {
      status = .normal
    } else if delta >= -50 {
      status = .fast
    } else {
      status = .urgent
    }

    return QuotaPaceEvaluation(
      status: status,
      idealRemainingPercent: idealRemaining,
      deltaPercent: delta)
  }
}

struct QuotaResetCredits: Codable, Equatable, Sendable {
  let availableCount: Int
  let expirationDates: [Date]

  init(availableCount: Int, expirationDates: [Date]) {
    self.availableCount = max(0, availableCount)
    self.expirationDates = expirationDates.sorted()
  }

  var nextExpirationDate: Date? {
    self.expirationDates.first
  }
}

enum QuotaFreshness: String, Codable, Equatable, Sendable {
  case fresh
  case cached
  case stale
  case authRequired
  case unavailable
}

struct QuotaSnapshot: Codable, Equatable, Identifiable, Sendable {
  let provider: QuotaProvider
  let session: QuotaWindow?
  let weekly: QuotaWindow?
  let resetCredits: QuotaResetCredits?
  let accountEmail: String?
  let source: String
  let updatedAt: Date
  let freshness: QuotaFreshness
  let message: String?

  var id: QuotaProvider { self.provider }

  var hasQuotaData: Bool {
    self.session != nil || self.weekly != nil
  }

  func markingCached(now: Date = Date(), staleAfter: TimeInterval) -> QuotaSnapshot {
    let age = max(0, now.timeIntervalSince(self.updatedAt))
    return self.replacing(
      freshness: age >= staleAfter ? .stale : .cached,
      message: age >= staleAfter ? "数据超过 5 分钟未更新" : "正在显示上次成功数据")
  }

  func markingFailure(
    _ message: String,
    now: Date = Date(),
    staleAfter: TimeInterval
  ) -> QuotaSnapshot {
    let age = max(0, now.timeIntervalSince(self.updatedAt))
    return self.replacing(
      freshness: age >= staleAfter ? .stale : .cached,
      message: message)
  }

  private func replacing(freshness: QuotaFreshness, message: String?) -> QuotaSnapshot {
    QuotaSnapshot(
      provider: self.provider,
      session: self.session,
      weekly: self.weekly,
      resetCredits: self.resetCredits,
      accountEmail: self.accountEmail,
      source: self.source,
      updatedAt: self.updatedAt,
      freshness: freshness,
      message: message)
  }
}

struct QuotaCache: Codable, Sendable {
  let version: Int
  let snapshots: [QuotaSnapshot]

  init(snapshots: [QuotaSnapshot]) {
    self.version = 1
    self.snapshots = snapshots
  }
}
