import Foundation

private struct QuotaRefreshOutcome: Sendable {
  let provider: QuotaProvider
  let snapshot: QuotaSnapshot?
  let errorDescription: String?
  let wasCancelled: Bool
}

enum QuotaRefreshPolicy {
  static func isDue(
    lastAttemptAt: Date?,
    now: Date,
    refreshInterval: TimeInterval
  ) -> Bool {
    guard let lastAttemptAt else { return true }
    return now.timeIntervalSince(lastAttemptAt) >= refreshInterval
  }
}

@MainActor
final class QuotaStore: ObservableObject {
  static let defaultRefreshInterval: TimeInterval = 120
  static let defaultStaleAfter: TimeInterval = 300

  @Published private(set) var snapshots: [QuotaProvider: QuotaSnapshot] = [:]
  @Published private(set) var isRefreshing = false
  @Published private(set) var lastRefreshAttempt: Date?

  private let fetcher: any QuotaFetching
  private let cacheStore: QuotaCacheStore
  private let refreshInterval: TimeInterval
  private let staleAfter: TimeInterval
  private var activeProviders = Set(QuotaProviderCatalog.orderedProviders)
  private var lastAttemptByProvider: [QuotaProvider: Date] = [:]
  private var inFlightTasks: [QuotaProvider: Task<Void, Never>] = [:]
  private var inFlightTokens: [QuotaProvider: UUID] = [:]
  private var timerTask: Task<Void, Never>?
  private var hasStarted = false

  init(
    fetcher: any QuotaFetching = CodexBarQuotaFetcher(),
    cacheStore: QuotaCacheStore = QuotaCacheStore(),
    refreshInterval: TimeInterval = QuotaStore.defaultRefreshInterval,
    staleAfter: TimeInterval = QuotaStore.defaultStaleAfter
  ) {
    self.fetcher = fetcher
    self.cacheStore = cacheStore
    self.refreshInterval = refreshInterval
    self.staleAfter = staleAfter

    let now = Date()
    self.snapshots = Dictionary(
      uniqueKeysWithValues: cacheStore.load().map { snapshot in
        (snapshot.provider, snapshot.markingCached(now: now, staleAfter: staleAfter))
      })
  }

  func start() {
    guard !self.hasStarted else { return }
    self.hasStarted = true
    self.refresh(providers: self.activeProviders, force: false)
  }

  func stop() {
    self.timerTask?.cancel()
    self.timerTask = nil
    for task in self.inFlightTasks.values {
      task.cancel()
    }
    self.inFlightTasks.removeAll()
    self.inFlightTokens.removeAll()
    self.hasStarted = false
    self.isRefreshing = false
  }

  func setActiveProviders(_ providers: Set<QuotaProvider>) {
    guard providers != self.activeProviders else { return }

    let newlyEnabled = providers.subtracting(self.activeProviders)
    self.activeProviders = providers

    guard self.hasStarted else { return }
    self.refresh(providers: newlyEnabled, force: false)
    self.scheduleNextRefresh()
  }

  func refresh() {
    self.refresh(providers: self.activeProviders, force: true)
  }

  func snapshot(for provider: QuotaProvider) -> QuotaSnapshot? {
    self.snapshots[provider]
  }

  private func refresh(providers: Set<QuotaProvider>, force: Bool) {
    guard self.hasStarted else { return }

    let now = Date()
    for provider in providers where self.activeProviders.contains(provider) {
      guard self.inFlightTasks[provider] == nil else { continue }
      guard force || QuotaRefreshPolicy.isDue(
        lastAttemptAt: self.lastAttemptByProvider[provider],
        now: now,
        refreshInterval: self.refreshInterval)
      else {
        continue
      }
      self.startRefresh(provider: provider, now: now)
    }
    self.scheduleNextRefresh()
  }

  private func startRefresh(provider: QuotaProvider, now: Date) {
    let token = UUID()
    let fetcher = self.fetcher

    self.lastAttemptByProvider[provider] = now
    self.lastRefreshAttempt = now
    self.inFlightTokens[provider] = token
    self.isRefreshing = true

    self.inFlightTasks[provider] = Task { [weak self] in
      let outcome: QuotaRefreshOutcome
      do {
        let snapshot = try await fetcher.fetch(provider)
        outcome = QuotaRefreshOutcome(
          provider: provider,
          snapshot: snapshot,
          errorDescription: nil,
          wasCancelled: false)
      } catch is CancellationError {
        outcome = QuotaRefreshOutcome(
          provider: provider,
          snapshot: nil,
          errorDescription: nil,
          wasCancelled: true)
      } catch {
        outcome = QuotaRefreshOutcome(
          provider: provider,
          snapshot: nil,
          errorDescription: error.localizedDescription,
          wasCancelled: false)
      }

      guard let self else { return }
      self.finishRefresh(outcome, token: token)
    }
  }

  private func finishRefresh(_ outcome: QuotaRefreshOutcome, token: UUID) {
    guard self.inFlightTokens[outcome.provider] == token else { return }

    self.inFlightTasks.removeValue(forKey: outcome.provider)
    self.inFlightTokens.removeValue(forKey: outcome.provider)

    if !outcome.wasCancelled {
      let now = Date()
      if let snapshot = outcome.snapshot {
        self.snapshots[outcome.provider] = snapshot
      } else if let message = outcome.errorDescription {
        self.applyFailure(provider: outcome.provider, message: message, now: now)
      }
      self.cacheStore.save(Array(self.snapshots.values))
    }

    self.isRefreshing = !self.inFlightTasks.isEmpty
    self.scheduleNextRefresh()
  }

  private func scheduleNextRefresh() {
    self.timerTask?.cancel()
    self.timerTask = nil

    guard self.hasStarted else { return }

    let now = Date()
    let nextDate = self.activeProviders.compactMap { provider -> Date? in
      guard self.inFlightTasks[provider] == nil else { return nil }
      guard let lastAttempt = self.lastAttemptByProvider[provider] else { return now }
      return lastAttempt.addingTimeInterval(self.refreshInterval)
    }.min()

    guard let nextDate else { return }
    let delay = max(0.05, nextDate.timeIntervalSince(now))
    self.timerTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      guard let self, !Task.isCancelled else { return }
      self.timerTask = nil
      self.refresh(providers: self.activeProviders, force: false)
    }
  }

  private func applyFailure(provider: QuotaProvider, message: String, now: Date) {
    if let previous = self.snapshots[provider], previous.hasQuotaData {
      self.snapshots[provider] = previous.markingFailure(
        Self.userFacingMessage(provider: provider, message: message),
        now: now,
        staleAfter: self.staleAfter)
      return
    }

    self.snapshots[provider] = QuotaSnapshot(
      provider: provider,
      session: nil,
      weekly: nil,
      resetCredits: nil,
      accountEmail: nil,
      source: "auto",
      updatedAt: now,
      freshness: Self.failureState(message),
      message: Self.userFacingMessage(provider: provider, message: message))
  }

  private static func failureState(_ message: String) -> QuotaFreshness {
    let lower = message.lowercased()
    let authMarkers = [
      "unauthorized", "token", "credential", "api key", "login", "log in", "authenticate", "scope",
    ]
    return authMarkers.contains(where: lower.contains) ? .authRequired : .unavailable
  }

  private static func userFacingMessage(provider: QuotaProvider, message: String) -> String {
    switch Self.failureState(message) {
    case .authRequired:
      provider.definition.credential == .kimiCodingPlanAPIKey
        ? "请右键设置 Kimi Coding Plan API Key"
        : "登录已失效，请重新登录对应 CLI"
    default:
      message
    }
  }
}
