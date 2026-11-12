import AppKit
import Foundation

enum CodexHomeResolver {
  static func resolvedEnvironment(
    from environment: [String: String],
    fileManager: FileManager = .default,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> [String: String] {
    guard
      (environment["CODEX_HOME"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let home = self.preferredHome(fileManager: fileManager, homeDirectory: homeDirectory)
    else {
      return environment
    }

    var resolved = environment
    resolved["CODEX_HOME"] = home.path
    return resolved
  }

  static func preferredHome(
    fileManager: FileManager = .default,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL? {
    self.candidateHomes(fileManager: fileManager, homeDirectory: homeDirectory)
      .compactMap { home -> Candidate? in
        let authFile = home.appendingPathComponent("auth.json", isDirectory: false)
        guard
          fileManager.fileExists(atPath: authFile.path),
          let data = try? Data(contentsOf: authFile),
          let metadata = AuthMetadata(data: data)
        else {
          return nil
        }
        return Candidate(home: home, metadata: metadata)
      }
      .sorted { lhs, rhs in
        if lhs.metadata.lastRefresh != rhs.metadata.lastRefresh {
          return (lhs.metadata.lastRefresh ?? .distantPast)
            > (rhs.metadata.lastRefresh ?? .distantPast)
        }
        return lhs.home.path < rhs.home.path
      }
      .first?
      .home
  }

  private static func candidateHomes(
    fileManager: FileManager,
    homeDirectory: URL
  ) -> [URL] {
    var homes = [homeDirectory.appendingPathComponent(".codex", isDirectory: true)]
    let accountsRoot = homeDirectory.appendingPathComponent(".codex-accounts", isDirectory: true)
    if let accountHomes = try? fileManager.contentsOfDirectory(
      at: accountsRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [])
    {
      homes.append(contentsOf: accountHomes)
    }
    return homes
  }

  private struct Candidate {
    let home: URL
    let metadata: AuthMetadata
  }

  struct AuthMetadata {
    let lastRefresh: Date?

    init?(data: Data) {
      guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let tokens = json["tokens"] as? [String: Any],
        Self.nonEmptyString(tokens["access_token"]) != nil,
        Self.nonEmptyString(tokens["refresh_token"]) != nil
      else {
        return nil
      }
      self.lastRefresh = Self.parseDate(json["last_refresh"])
    }

    private static func nonEmptyString(_ raw: Any?) -> String? {
      guard let value = raw as? String else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDate(_ raw: Any?) -> Date? {
      guard let value = raw as? String, !value.isEmpty else { return nil }
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      return formatter.date(from: value)
    }
  }
}

struct ClaudeOAuthEnvironmentCredentials: Equatable, Sendable {
  let accessToken: String
  let scopes: [String]
}

struct ClaudeOAuthSecurityCLILoader: Sendable {
  private static let service = "Claude Code-credentials"
  private static let securityBinary = "/usr/bin/security"

  func load() async -> ClaudeOAuthEnvironmentCredentials? {
    await Task.detached(priority: .utility) {
      Self.loadSynchronously()
    }.value
  }

  static func parse(_ data: Data) -> ClaudeOAuthEnvironmentCredentials? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let oauth = root["claudeAiOauth"] as? [String: Any],
      let rawToken = oauth["accessToken"] as? String
    else {
      return nil
    }

    let accessToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !accessToken.isEmpty else { return nil }

    let scopes =
      (oauth["scopes"] as? [String])?
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      ?? []

    return ClaudeOAuthEnvironmentCredentials(
      accessToken: accessToken,
      scopes: scopes.isEmpty ? ["user:profile"] : scopes)
  }

  private static func loadSynchronously() -> ClaudeOAuthEnvironmentCredentials? {
    guard FileManager.default.isExecutableFile(atPath: Self.securityBinary) else { return nil }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: Self.securityBinary)
    process.arguments = [
      "find-generic-password",
      "-s",
      Self.service,
      "-w",
    ]

    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return nil
    }

    let deadline = Date().addingTimeInterval(3)
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    if process.isRunning {
      process.terminate()
      return nil
    }
    guard process.terminationStatus == 0 else { return nil }

    return Self.parse(output.fileHandleForReading.readDataToEndOfFile())
  }
}

struct KimiAPIKeyStore: Sendable {
  let fileURL: URL

  init(fileURL: URL = Self.defaultFileURL()) {
    self.fileURL = fileURL
  }

  func load() -> String? {
    guard let data = try? Data(contentsOf: self.fileURL),
      let raw = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  func save(_ apiKey: String) throws {
    let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { throw KimiAPIKeyStoreError.emptyKey }

    let directory = self.fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try Data((value + "\n").utf8).write(to: self.fileURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: self.fileURL.path)
  }

  func clear() throws {
    guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
    try FileManager.default.removeItem(at: self.fileURL)
  }

  private static func defaultFileURL() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser
    return root
      .appendingPathComponent("QuotaFloat", isDirectory: true)
      .appendingPathComponent("kimi-code-api-key", isDirectory: false)
  }
}

enum KimiAPIKeyStoreError: LocalizedError {
  case emptyKey

  var errorDescription: String? {
    "Kimi Coding Plan API Key不能为空。"
  }
}

@MainActor
final class ProviderCredentialPreferences: ObservableObject {
  let kimiAPIKeyStore: KimiAPIKeyStore
  @Published private(set) var hasKimiAPIKey: Bool

  init(kimiAPIKeyStore: KimiAPIKeyStore = KimiAPIKeyStore()) {
    self.kimiAPIKeyStore = kimiAPIKeyStore
    self.hasKimiAPIKey = kimiAPIKeyStore.load() != nil
  }

  @discardableResult
  func promptForKimiAPIKey() -> Bool {
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    field.placeholderString = self.hasKimiAPIKey ? "输入新的 API Key以替换现有配置" : "KIMI_CODE_API_KEY"

    let alert = NSAlert()
    alert.messageText = "设置 Kimi Coding Plan API Key"
    alert.informativeText =
      "API Key仅保存在本机 QuotaFloat配置目录中，文件权限为仅当前用户可读，不写入钥匙串。"
    alert.alertStyle = .informational
    alert.accessoryView = field
    alert.addButton(withTitle: "保存")
    alert.addButton(withTitle: "取消")

    NSApplication.shared.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return false }

    do {
      try self.kimiAPIKeyStore.save(field.stringValue)
      self.hasKimiAPIKey = true
      return true
    } catch {
      Self.showError(error.localizedDescription)
      return false
    }
  }

  @discardableResult
  func confirmAndClearKimiAPIKey() -> Bool {
    let alert = NSAlert()
    alert.messageText = "清除 Kimi API Key？"
    alert.informativeText = "清除后 Kimi额度将停止刷新，直到重新设置 API Key。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "清除")
    alert.addButton(withTitle: "取消")
    guard alert.runModal() == .alertFirstButtonReturn else { return false }

    do {
      try self.kimiAPIKeyStore.clear()
      self.hasKimiAPIKey = false
      return true
    } catch {
      Self.showError(error.localizedDescription)
      return false
    }
  }

  private static func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "无法保存 Kimi API Key"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.runModal()
  }
}
