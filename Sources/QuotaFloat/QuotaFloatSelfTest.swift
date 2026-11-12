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

  static func run() async throws {
    try self.checkDisplayRecovery()
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

    let codexRoot = directory.appendingPathComponent("codex-home-resolution", isDirectory: true)
    let defaultCodexHome = codexRoot.appendingPathComponent(".codex", isDirectory: true)
    let accountOneHome = codexRoot
      .appendingPathComponent(".codex-accounts", isDirectory: true)
      .appendingPathComponent("account1", isDirectory: true)
    try FileManager.default.createDirectory(
      at: defaultCodexHome,
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: accountOneHome,
      withIntermediateDirectories: true)
    try self.writeCodexAuth(
      at: defaultCodexHome,
      lastRefresh: "2026-06-15T13:53:41.717835Z")
    try self.writeCodexAuth(
      at: accountOneHome,
      lastRefresh: "2026-06-25T01:30:42Z")
    let resolvedCodexHome = CodexHomeResolver.preferredHome(homeDirectory: codexRoot)
    try self.check(
      resolvedCodexHome?.standardizedFileURL.path == accountOneHome.standardizedFileURL.path,
      "Codex home resolver must prefer the freshest Codex account auth")
    try self.check(
      URL(fileURLWithPath: CodexHomeResolver.resolvedEnvironment(
        from: [:],
        homeDirectory: codexRoot)["CODEX_HOME"] ?? "")
        .standardizedFileURL.path == accountOneHome.standardizedFileURL.path,
      "Codex environment must inject CODEX_HOME for GUI launches")
    try self.check(
      CodexHomeResolver.resolvedEnvironment(
        from: ["CODEX_HOME": defaultCodexHome.path],
        homeDirectory: codexRoot
      )["CODEX_HOME"] == defaultCodexHome.path,
      "Explicit CODEX_HOME must not be overridden")

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
      QuotaProviderCatalog.orderedProviders
        == [.codex, .claude, .kimi, .antigravityGemini, .antigravityClaudeGPT],
      "provider catalog must drive the visible provider order")

    try self.checkAntigravityMapping(cache: cache)
    try await self.checkGroupedRefresh(directory: directory)

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

    if let index = CommandLine.arguments.firstIndex(of: "--preview-output"),
      CommandLine.arguments.indices.contains(index + 1)
    {
      let usage = self.antigravityUsage(now: Date())
      let existingValues: [(QuotaProvider, Double, Double)] = [(.codex, 18, 33), (.claude, 44, 47), (.kimi, 0, 78)]
      let existing = existingValues.map { provider, sessionRemaining, weeklyRemaining in
        QuotaSnapshot(
          provider: provider,
          session: QuotaWindow(usedPercent: 100 - sessionRemaining, resetsAt: nil, windowMinutes: 300),
          weekly: QuotaWindow(usedPercent: 100 - weeklyRemaining, resetsAt: nil, windowMinutes: 10_080),
          resetCredits: nil, accountEmail: nil, source: "preview",
          updatedAt: usage.updatedAt, freshness: .fresh, message: nil)
      }
      let snapshots = existing + QuotaProvider.antigravityGemini.refreshGroup.map {
        CodexBarQuotaFetcher.mapSnapshot(usage, provider: $0, source: "preview")
      }
      try FloatingQuotaView.renderPreview(
        snapshots: snapshots,
        to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    }
    if CommandLine.arguments.contains("--live-antigravity") {
      let snapshots = try await CodexBarQuotaFetcher().fetch(.antigravityGemini)
      for snapshot in snapshots {
        let session = snapshot.session.map { String(Int($0.remainingPercent.rounded())) + "%" } ?? "--"
        let weekly = snapshot.weekly.map { String(Int($0.remainingPercent.rounded())) + "%" } ?? "--"
        print("\(snapshot.provider.displayName): 5h \(session), 周 \(weekly), 来源 \(snapshot.source)")
        print("  5h \(ResetTimeFormatter.string(snapshot.session, now: Date()))")
        print("  周 \(ResetTimeFormatter.string(snapshot.weekly, now: Date()))")
      }
    }
  }

  private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw Failure.assertion(message) }
  }

  private static func checkDisplayRecovery() throws {
    let suite = "QuotaFloatDisplaySelfTest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(2, forKey: "QuotaFloatDisplayConfigurationVersion")
    defaults.set(false, forKey: "QuotaFloatAlwaysDisplay")
    defaults.set([String](), forKey: "QuotaFloatSelectedApps")
    let preferences = DisplayPreferences(defaults: defaults)
    try self.check(preferences.alwaysDisplay, "empty app selection must recover to visible mode on launch")
    preferences.toggleApp("com.openai.codex")
    try self.check(!preferences.alwaysDisplay, "a selected app must retain app-specific visibility")
    preferences.toggleApp("com.openai.codex")
    try self.check(preferences.alwaysDisplay, "disabling the last app must not hide the float everywhere")
    preferences.toggleTerminals()
    preferences.toggleTerminals()
    try self.check(preferences.alwaysDisplay, "disabling the last terminal group must recover visibility")
    try self.check(
      DisplayPreferences(defaults: defaults).alwaysDisplay,
      "recovered visibility must survive a restart")
  }

  static func antigravityUsage(now: Date) -> UsageSnapshot {
    let buckets: [(String, String, Double, Int, TimeInterval)] = [
      ("3p-weekly", "Claude and GPT models Weekly limit", 3, 10_080, 6 * 86_400 + 22 * 3_600),
      ("gemini-5h", "Gemini Models 5h limit", 3, 300, 4 * 3_600 + 9 * 60),
      ("3p-5h", "Claude and GPT models 5h limit", 5, 300, 3 * 3_600 + 51 * 60),
      ("gemini-weekly", "Gemini Models Weekly limit", 1, 10_080, 6 * 86_400 + 23 * 3_600),
    ]
    return UsageSnapshot(
      primary: RateWindow(usedPercent: 3, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
      secondary: RateWindow(usedPercent: 5, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
      extraRateWindows: buckets.map { id, title, used, minutes, remaining in
        NamedRateWindow(
          id: "antigravity-quota-summary-" + id,
          title: title,
          window: RateWindow(
            usedPercent: used, windowMinutes: minutes,
            resetsAt: now.addingTimeInterval(remaining), resetDescription: nil))
      },
      updatedAt: now)
  }

  private static func checkAntigravityMapping(cache: QuotaCacheStore) throws {
    let now = Date()
    let usage = self.antigravityUsage(now: now)
    let gemini = CodexBarQuotaFetcher.mapSnapshot(usage, provider: .antigravityGemini, source: "app")
    let claudeGPT = CodexBarQuotaFetcher.mapSnapshot(usage, provider: .antigravityClaudeGPT, source: "app")
    try self.check(
      gemini.session?.remainingPercent == 97 && gemini.weekly?.remainingPercent == 99
        && claudeGPT.session?.remainingPercent == 95 && claudeGPT.weekly?.remainingPercent == 97,
      "shuffled Gemini and Claude/GPT buckets must map to four independent quota windows")
    try self.check(
      gemini.session?.resetsAt == now.addingTimeInterval(4 * 3_600 + 9 * 60)
        && claudeGPT.weekly?.resetsAt == now.addingTimeInterval(6 * 86_400 + 22 * 3_600),
      "each quota window must keep its own reset time")

    let unknown = UsageSnapshot(
      primary: usage.primary, secondary: usage.secondary,
      extraRateWindows: usage.extraRateWindows?.map {
        NamedRateWindow(id: $0.id, title: $0.title, window: $0.window, usageKnown: false)
      }, updatedAt: now)
    try self.check(
      !CodexBarQuotaFetcher.mapSnapshot(unknown, provider: .antigravityGemini, source: "app").hasQuotaData,
      "unknown quota buckets must not become 100% or fall back to a representative window")

    let partial = UsageSnapshot(
      primary: usage.primary, secondary: usage.secondary,
      extraRateWindows: usage.extraRateWindows?.filter { $0.id.hasSuffix("gemini-weekly") },
      updatedAt: now)
    let partialGemini = CodexBarQuotaFetcher.mapSnapshot(partial, provider: .antigravityGemini, source: "app")
    try self.check(
      partialGemini.session == nil && partialGemini.weekly?.remainingPercent == 99
        && !CodexBarQuotaFetcher.mapSnapshot(partial, provider: .antigravityClaudeGPT, source: "app").hasQuotaData,
      "missing summary buckets must not borrow another group or use the compact representative")

    let legacy = UsageSnapshot(primary: usage.primary, secondary: usage.secondary, updatedAt: now)
    let legacyGemini = CodexBarQuotaFetcher.mapSnapshot(legacy, provider: .antigravityGemini, source: "ide")
    let legacyClaude = CodexBarQuotaFetcher.mapSnapshot(legacy, provider: .antigravityClaudeGPT, source: "ide")
    try self.check(
      legacyGemini.session?.remainingPercent == 97 && legacyClaude.session?.remainingPercent == 95
        && legacyGemini.weekly == nil && legacyClaude.weekly == nil,
      "legacy model pools must remain separate sessions, never fabricated weekly quotas")
    cache.save([gemini, claudeGPT])
    let restored = cache.load()
    try self.check(
      restored.map(\.provider) == [.antigravityGemini, .antigravityClaudeGPT]
        && restored[0].weekly?.remainingPercent == 99 && restored[1].session?.remainingPercent == 95,
      "both quota groups must survive a cache round trip independently")

    let geminiAddedWidth = ProviderStripLayout.width(for: .antigravityGemini)
      - ProviderStripLayout.nameWidth(for: .antigravityGemini)
    let claudeAddedWidth = ProviderStripLayout.width(for: .antigravityClaudeGPT)
      - ProviderStripLayout.nameWidth(for: .antigravityClaudeGPT)
    try self.check(
      geminiAddedWidth == claudeAddedWidth,
      "both names must use the same trailing gap rather than a fixed-width name column")
  }

  private static func checkGroupedRefresh(directory: URL) async throws {
    let usage = self.antigravityUsage(now: Date())
    let snapshots = QuotaProvider.antigravityGemini.refreshGroup.map {
      CodexBarQuotaFetcher.mapSnapshot(usage, provider: $0, source: "fixture")
    }
    let fetcher = GroupedQuotaTestFetcher(snapshots: snapshots)
    let store = QuotaStore(
      fetcher: fetcher,
      cacheStore: QuotaCacheStore(fileURL: directory.appendingPathComponent("grouped-cache.json")))
    defer { store.stop() }
    store.setActiveProviders([.antigravityClaudeGPT])
    store.start()
    store.setActiveProviders([.antigravityGemini, .antigravityClaudeGPT])
    store.refresh()
    try await self.waitForRefresh(store)
    let initialRequests = await fetcher.requests
    try self.check(initialRequests == [.antigravityGemini], "two visible groups must share one in-flight fetch")
    try self.check(
      store.snapshot(for: .antigravityGemini)?.weekly?.remainingPercent == 99
        && store.snapshot(for: .antigravityClaudeGPT)?.session?.remainingPercent == 95,
      "one fetch must update both group snapshots")
    store.setActiveProviders([.antigravityGemini])
    store.setActiveProviders([.antigravityClaudeGPT])
    try self.check(!store.isRefreshing, "switching groups must share the two-minute refresh interval")
    await fetcher.failNextRequest()
    store.refresh()
    try await self.waitForRefresh(store)
    let requests = await fetcher.requests
    try self.check(requests.count == 2, "manual refresh must bypass the interval exactly once")
    try self.check(
      store.snapshot(for: .antigravityGemini)?.freshness == .cached
        && store.snapshot(for: .antigravityClaudeGPT)?.freshness == .cached,
      "a shared fetch failure must preserve both previously successful snapshots")
  }

  private static func waitForRefresh(_ store: QuotaStore) async throws {
    for _ in 0..<200 {
      if !store.isRefreshing { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw Failure.assertion("grouped refresh did not finish")
  }

  private static func writeCodexAuth(at home: URL, lastRefresh: String) throws {
    let data = Data(
      """
      {
        "auth_mode": "chatgpt",
        "last_refresh": "\(lastRefresh)",
        "tokens": {
          "access_token": "access",
          "refresh_token": "refresh",
          "id_token": "id",
          "account_id": "account"
        }
      }
      """.utf8)
    try data.write(to: home.appendingPathComponent("auth.json", isDirectory: false))
  }
}

private actor GroupedQuotaTestFetcher: QuotaFetching {
  let snapshots: [QuotaSnapshot]
  private(set) var requests: [QuotaProvider] = []
  private var shouldFail = false

  init(snapshots: [QuotaSnapshot]) {
    self.snapshots = snapshots
  }

  func failNextRequest() {
    self.shouldFail = true
  }

  func fetch(_ provider: QuotaProvider) async throws -> [QuotaSnapshot] {
    self.requests.append(provider)
    try await Task.sleep(for: .milliseconds(10))
    if self.shouldFail { throw URLError(.notConnectedToInternet) }
    return self.snapshots
  }
}
