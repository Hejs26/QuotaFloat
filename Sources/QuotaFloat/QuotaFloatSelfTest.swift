import CodexBarCore
import Foundation

@MainActor
enum QuotaFloatSelfTest {
  enum Failure: LocalizedError {
    case assertion(String)

    var errorDescription: String? {
      switch self {
      case .assertion(let message): message
      }
    }
  }

  static func run() throws {
    try self.check(
      KeychainAccessGate.isDisabled,
      "QuotaFloat must keep CodexBarCore keychain access disabled")

    let claudeCredentialFixture = Data(
      """
      {
        "claudeAiOauth": {
          "accessToken": "test-token",
          "scopes": ["user:profile", "user:inference"]
        }
      }
      """.utf8)
    try self.check(
      ClaudeOAuthSecurityCLILoader.parse(claudeCredentialFixture)
        == ClaudeOAuthEnvironmentCredentials(
          accessToken: "test-token",
          scopes: ["user:profile", "user:inference"]),
      "Claude OAuth security CLI output must map to the non-interactive environment source")

    try self.check(
      QuotaWindow(usedPercent: -10, resetsAt: nil, windowMinutes: 300).usedPercent == 0,
      "negative usage must clamp to zero")
    try self.check(
      QuotaWindow(usedPercent: 140, resetsAt: nil, windowMinutes: 300).usedPercent == 100,
      "usage above 100 must clamp")
    try self.check(
      QuotaWindow(usedPercent: .infinity, resetsAt: nil, windowMinutes: 300).usedPercent == 0,
      "non-finite usage must normalize")

    let paceNow = Date(timeIntervalSince1970: 20_000)
    let halfWindowReset = paceNow.addingTimeInterval(150 * 60)
    try self.check(
      QuotaWindow(
        usedPercent: 45,
        resetsAt: halfWindowReset,
        windowMinutes: 300
      ).paceEvaluation(now: paceNow)?.status == .roomy,
      "+5% remaining delta must be roomy")
    try self.check(
      QuotaWindow(
        usedPercent: 50,
        resetsAt: halfWindowReset,
        windowMinutes: 300
      ).paceEvaluation(now: paceNow)?.status == .normal,
      "zero remaining delta must be normal")
    try self.check(
      QuotaWindow(
        usedPercent: 55,
        resetsAt: halfWindowReset,
        windowMinutes: 300
      ).paceEvaluation(now: paceNow)?.status == .fast,
      "-5% remaining delta must be fast")
    try self.check(
      QuotaWindow(
        usedPercent: 70,
        resetsAt: paceNow.addingTimeInterval(240 * 60),
        windowMinutes: 300
      ).paceEvaluation(now: paceNow)?.status == .fast,
      "-50% remaining delta must still be fast")
    try self.check(
      QuotaWindow(
        usedPercent: 80,
        resetsAt: paceNow.addingTimeInterval(240 * 60),
        windowMinutes: 300
      ).paceEvaluation(now: paceNow)?.status == .urgent,
      "remaining delta below -50% must be urgent")
    try self.check(
      QuotaWindow(
        usedPercent: 100,
        resetsAt: nil,
        windowMinutes: 300
      ).paceEvaluation(now: paceNow)?.status == .exhausted,
      "zero actual remaining must always be exhausted")
    try self.check(
      QuotaWindow(
        usedPercent: 20,
        resetsAt: nil,
        windowMinutes: 300
      ).paceEvaluation(now: paceNow) == nil,
      "pace must stay hidden when reset time is unavailable")

    let updatedAt = Date(timeIntervalSince1970: 1_000)
    let snapshot = QuotaSnapshot(
      provider: .codex,
      session: QuotaWindow(usedPercent: 25, resetsAt: nil, windowMinutes: 300),
      weekly: QuotaWindow(usedPercent: 40, resetsAt: nil, windowMinutes: 10_080),
      resetCredits: QuotaResetCredits(
        availableCount: 2,
        expirationDates: [
          updatedAt.addingTimeInterval(7_200),
          updatedAt.addingTimeInterval(3_600),
        ]),
      accountEmail: "user@example.com",
      source: "oauth",
      updatedAt: updatedAt,
      freshness: .fresh,
      message: nil)
    try self.check(
      snapshot.markingCached(
        now: updatedAt.addingTimeInterval(299),
        staleAfter: 300
      ).freshness == .cached,
      "recent cached snapshot must stay cached")
    try self.check(
      snapshot.markingCached(
        now: updatedAt.addingTimeInterval(300),
        staleAfter: 300
      ).freshness == .stale,
      "old cached snapshot must become stale")
    try self.check(
      snapshot.resetCredits?.availableCount == 2,
      "Codex reset-credit count must survive snapshot mapping")
    try self.check(
      snapshot.resetCredits?.nextExpirationDate == updatedAt.addingTimeInterval(3_600),
      "Codex reset-credit expiration dates must be sorted")

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("QuotaFloatSelfTest-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = QuotaCacheStore(fileURL: directory.appendingPathComponent("quota-cache.json"))
    cache.save([snapshot])
    try self.check(cache.load() == [snapshot], "cache round trip must preserve quota data")

    let kimiKeyStore = KimiAPIKeyStore(fileURL: directory.appendingPathComponent("kimi-api-key"))
    try kimiKeyStore.save("test-kimi-key")
    try self.check(kimiKeyStore.load() == "test-kimi-key", "Kimi API key must round trip")
    let keyAttributes = try FileManager.default.attributesOfItem(atPath: kimiKeyStore.fileURL.path)
    let keyPermissions = (keyAttributes[.posixPermissions] as? NSNumber)?.intValue
    try self.check(keyPermissions == 0o600, "Kimi API key file must be readable only by the current user")
    try kimiKeyStore.clear()
    try self.check(kimiKeyStore.load() == nil, "Kimi API key must be removable")

    let weeklyOnly = UsageSnapshot(
      primary: RateWindow(
        usedPercent: 30,
        windowMinutes: 10_080,
        resetsAt: nil,
        resetDescription: nil),
      secondary: nil,
      updatedAt: updatedAt)
    let mapped = CodexBarQuotaFetcher.mapWindows(
      weeklyOnly,
      definition: QuotaProvider.codex.definition)
    try self.check(
      mapped.session == nil, "weekly-only data must not be duplicated into the 5-hour lane")
    try self.check(
      mapped.weekly?.windowMinutes == 10_080, "weekly-only data must stay in the weekly lane")

    let kimiUsage = UsageSnapshot(
      primary: RateWindow(
        usedPercent: 30,
        windowMinutes: nil,
        resetsAt: updatedAt.addingTimeInterval(7 * 24 * 60 * 60),
        resetDescription: nil),
      secondary: RateWindow(
        usedPercent: 40,
        windowMinutes: 300,
        resetsAt: updatedAt.addingTimeInterval(5 * 60 * 60),
        resetDescription: nil),
      updatedAt: updatedAt)
    let kimiMapped = CodexBarQuotaFetcher.mapWindows(
      kimiUsage,
      definition: QuotaProvider.kimi.definition)
    try self.check(
      kimiMapped.session?.windowMinutes == 300,
      "Kimi 5-hour rate limit must map to the session lane")
    try self.check(
      kimiMapped.weekly?.windowMinutes == 10_080,
      "Kimi weekly quota must receive an explicit seven-day duration")

    try self.check(
      QuotaProviderCatalog.orderedProviders == [.codex, .claude, .kimi],
      "provider catalog must drive the visible provider order")

    let contentPreferences = ContentPreferences()
    try self.check(
      contentPreferences.selectedProviders == Set(QuotaProviderCatalog.orderedProviders),
      "all catalog providers must be selected by default")
    try self.check(
      contentPreferences.multiResetPinned == false,
      "multi-provider reset details must be hidden by default")
    let multiUnpinnedWidth = contentPreferences.designSize.width
    contentPreferences.setMultiResetPinned(true)
    try self.check(
      contentPreferences.designSize.width
        == multiUnpinnedWidth + CGFloat(QuotaProviderCatalog.orderedProviders.count) * 124,
      "pinning multiple providers must add the single-provider reset width to every provider")
    contentPreferences.setMultiResetPinned(false)
    contentPreferences.setSelectedProviders([.kimi])
    try self.check(
      contentPreferences.activeProviders == [.kimi],
      "single-provider selection must be data driven")
    contentPreferences.toggle(.kimi)
    try self.check(
      contentPreferences.activeProviders == [.kimi],
      "the last selected provider must not be removable")
    contentPreferences.selectAll()
    contentPreferences.collapse()
    try self.check(
      contentPreferences.activeProviders.isEmpty,
      "collapsed mode must pause all provider refreshes")
    try self.check(
      contentPreferences.designSize == NSSize(width: 126, height: 40),
      "collapsed mode must use the compact brand size")
    contentPreferences.expandAll()
    try self.check(
      contentPreferences.activeProviders == Set(QuotaProviderCatalog.orderedProviders),
      "expanding globally must restore all providers")

    let refreshNow = Date(timeIntervalSince1970: 10_000)
    try self.check(
      QuotaRefreshPolicy.isDue(
        lastAttemptAt: nil,
        now: refreshNow,
        refreshInterval: 120),
      "a provider with no request history must refresh immediately")
    try self.check(
      !QuotaRefreshPolicy.isDue(
        lastAttemptAt: refreshNow.addingTimeInterval(-119),
        now: refreshNow,
        refreshInterval: 120),
      "rapid content switching must not refresh again inside two minutes")
    try self.check(
      QuotaRefreshPolicy.isDue(
        lastAttemptAt: refreshNow.addingTimeInterval(-120),
        now: refreshNow,
        refreshInterval: 120),
      "a displayed provider must become due after two minutes")
  }

  private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw Failure.assertion(message) }
  }
}
