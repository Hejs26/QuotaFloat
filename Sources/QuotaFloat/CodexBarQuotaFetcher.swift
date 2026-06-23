import CodexBarCore
import Foundation

protocol QuotaFetching: Sendable {
  func fetch(_ provider: QuotaProvider) async throws -> QuotaSnapshot
}

enum QuotaFetchError: LocalizedError, Sendable {
  case noQuotaWindows(QuotaProvider)
  case missingCredential(QuotaProvider)

  var errorDescription: String? {
    switch self {
    case .noQuotaWindows(let provider):
      "\(provider.displayName) 没有返回 5 小时或周额度。"
    case .missingCredential(let provider):
      "请右键设置 \(provider.displayName) Coding Plan API Key。"
    }
  }
}

struct CodexBarQuotaFetcher: QuotaFetching {
  private let baseEnvironment: [String: String]
  private let kimiAPIKeyStore: KimiAPIKeyStore
  private let claudeOAuthLoader: ClaudeOAuthSecurityCLILoader
  private let browserDetection: BrowserDetection
  private let codexFetcher: UsageFetcher
  private let claudeFetcher: ClaudeUsageFetcher
  private let settings: ProviderSettingsSnapshot

  init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    kimiAPIKeyStore: KimiAPIKeyStore = KimiAPIKeyStore()
  ) {
    let browserDetection = BrowserDetection()
    self.baseEnvironment = environment
    self.kimiAPIKeyStore = kimiAPIKeyStore
    self.claudeOAuthLoader = ClaudeOAuthSecurityCLILoader()
    self.browserDetection = browserDetection
    self.codexFetcher = UsageFetcher(environment: environment)
    self.claudeFetcher = ClaudeUsageFetcher(
      browserDetection: browserDetection,
      environment: environment,
      runtime: .app,
      dataSource: .auto,
      useWebExtras: false)
    self.settings = ProviderSettingsSnapshot.make(
      codex: .init(
        usageDataSource: .auto,
        cookieSource: .off,
        manualCookieHeader: nil),
      claude: .init(
        usageDataSource: .auto,
        webExtrasEnabled: false,
        cookieSource: .off,
        manualCookieHeader: nil),
      kimi: .init(
        cookieSource: .off,
        manualCookieHeader: nil))
  }

  func fetch(_ provider: QuotaProvider) async throws -> QuotaSnapshot {
    let environment = await self.environment(for: provider)
    if provider.definition.credential == .kimiCodingPlanAPIKey,
      ProviderTokenResolver.kimiAPIToken(environment: environment) == nil
    {
      throw QuotaFetchError.missingCredential(provider)
    }
    let context = ProviderFetchContext(
      runtime: .app,
      sourceMode: .auto,
      includeCredits: false,
      includeOptionalUsage: provider == .codex,
      webTimeout: 30,
      webDebugDumpHTML: false,
      verbose: false,
      env: environment,
      settings: self.settings,
      fetcher: self.codexFetcher,
      claudeFetcher: self.claudeFetcher,
      browserDetection: self.browserDetection,
      costUsageHistoryDays: 30,
      persistsCLISessions: false)

    let definition = provider.definition
    let descriptor = ProviderDescriptorRegistry.descriptor(for: definition.coreProvider)
    let result = try await descriptor.fetch(context: context)

    let windows = Self.mapWindows(result.usage, definition: definition)
    guard windows.session != nil || windows.weekly != nil else {
      throw QuotaFetchError.noQuotaWindows(provider)
    }

    return QuotaSnapshot(
      provider: provider,
      session: windows.session,
      weekly: windows.weekly,
      resetCredits: Self.mapResetCredits(result.usage.codexResetCredits),
      accountEmail: result.usage.accountEmail(for: definition.coreProvider),
      source: result.sourceLabel,
      updatedAt: result.usage.updatedAt,
      freshness: .fresh,
      message: nil)
  }

  static func mapWindows(
    _ usage: UsageSnapshot,
    definition: QuotaProviderDefinition
  ) -> (
    session: QuotaWindow?, weekly: QuotaWindow?
  ) {
    let candidates = [usage.primary, usage.secondary, usage.tertiary].compactMap { $0 }

    let sessionSource: (window: RateWindow, assumedMinutes: Int?)? =
      candidates.first { window in
        guard let minutes = window.windowMinutes else { return false }
        return minutes > 0 && minutes <= 6 * 60
      }
      .map { ($0, nil) }
      ?? Self.fallbackWindow(
        usage: usage,
        fallback: definition.sessionFallback)

    let weeklySource: (window: RateWindow, assumedMinutes: Int?)? =
      candidates.first { window in
        guard let minutes = window.windowMinutes else { return false }
        return minutes >= 6 * 24 * 60 && minutes <= 8 * 24 * 60
      }
      .map { ($0, nil) }
      ?? Self.fallbackWindow(
        usage: usage,
        fallback: definition.weeklyFallback)

    return (
      session: sessionSource.map { Self.mapWindow($0.window, assumedMinutes: $0.assumedMinutes) },
      weekly: weeklySource.map { Self.mapWindow($0.window, assumedMinutes: $0.assumedMinutes) }
    )
  }

  private func environment(for provider: QuotaProvider) async -> [String: String] {
    var environment = self.baseEnvironment
    if provider == .claude,
      let credentials = await self.claudeOAuthLoader.load()
    {
      environment[ClaudeOAuthCredentialsStore.environmentTokenKey] = credentials.accessToken
      environment[ClaudeOAuthCredentialsStore.environmentScopesKey] =
        credentials.scopes.joined(separator: ",")
    }
    if provider.definition.credential == .kimiCodingPlanAPIKey,
      let apiKey = self.kimiAPIKeyStore.load()
    {
      environment["KIMI_CODE_API_KEY"] = apiKey
    }
    return environment
  }

  private static func fallbackWindow(
    usage: UsageSnapshot,
    fallback: QuotaWindowFallback
  ) -> (window: RateWindow, assumedMinutes: Int?)? {
    let window: RateWindow? = switch fallback.lane {
    case .primary: usage.primary
    case .secondary: usage.secondary
    case .tertiary: usage.tertiary
    }
    guard let window, window.windowMinutes == nil else { return nil }
    return (window, fallback.assumedMinutes)
  }

  private static func mapWindow(
    _ window: RateWindow,
    assumedMinutes: Int?
  ) -> QuotaWindow {
    QuotaWindow(
      usedPercent: window.usedPercent,
      resetsAt: window.resetsAt,
      windowMinutes: window.windowMinutes ?? assumedMinutes)
  }

  private static func mapResetCredits(
    _ snapshot: CodexRateLimitResetCreditsSnapshot?
  ) -> QuotaResetCredits? {
    guard let snapshot else { return nil }
    let expirationDates = snapshot.credits.compactMap { credit -> Date? in
      guard
        credit.status == .available,
        let expiresAt = credit.expiresAt,
        expiresAt > snapshot.updatedAt
      else {
        return nil
      }
      return expiresAt
    }
    return QuotaResetCredits(
      availableCount: snapshot.availableCount,
      expirationDates: expirationDates)
  }

}
