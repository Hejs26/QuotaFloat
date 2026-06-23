import CodexBarCore
import Foundation

enum QuotaProviderIcon: Sendable {
  case codex
  case claude
  case kimi
}

enum QuotaProviderCredential: Equatable, Sendable {
  case none
  case kimiCodingPlanAPIKey
}

enum QuotaWindowLane: Sendable {
  case primary
  case secondary
  case tertiary
}

struct QuotaWindowFallback: Sendable {
  let lane: QuotaWindowLane
  let assumedMinutes: Int
}

struct QuotaProviderColor: Sendable {
  let red: Double
  let green: Double
  let blue: Double
}

struct QuotaProviderDefinition: Sendable {
  let id: QuotaProvider
  let displayName: String
  let coreProvider: UsageProvider
  let icon: QuotaProviderIcon
  let color: QuotaProviderColor
  let credential: QuotaProviderCredential
  let sessionFallback: QuotaWindowFallback
  let weeklyFallback: QuotaWindowFallback
}

enum QuotaProviderCatalog {
  static let definitions: [QuotaProviderDefinition] = [
    QuotaProviderDefinition(
      id: .codex,
      displayName: "Codex",
      coreProvider: .codex,
      icon: .codex,
      color: QuotaProviderColor(red: 0.42, green: 0.33, blue: 0.96),
      credential: .none,
      sessionFallback: QuotaWindowFallback(lane: .primary, assumedMinutes: 300),
      weeklyFallback: QuotaWindowFallback(lane: .secondary, assumedMinutes: 10_080)),
    QuotaProviderDefinition(
      id: .claude,
      displayName: "Claude",
      coreProvider: .claude,
      icon: .claude,
      color: QuotaProviderColor(red: 0.87, green: 0.43, blue: 0.29),
      credential: .none,
      sessionFallback: QuotaWindowFallback(lane: .primary, assumedMinutes: 300),
      weeklyFallback: QuotaWindowFallback(lane: .secondary, assumedMinutes: 10_080)),
    QuotaProviderDefinition(
      id: .kimi,
      displayName: "Kimi",
      coreProvider: .kimi,
      icon: .kimi,
      color: QuotaProviderColor(red: 0.10, green: 0.10, blue: 0.12),
      credential: .kimiCodingPlanAPIKey,
      sessionFallback: QuotaWindowFallback(lane: .secondary, assumedMinutes: 300),
      weeklyFallback: QuotaWindowFallback(lane: .primary, assumedMinutes: 10_080)),
  ]

  private static let byID = Dictionary(uniqueKeysWithValues: Self.definitions.map { ($0.id, $0) })

  static func definition(for provider: QuotaProvider) -> QuotaProviderDefinition {
    guard let definition = Self.byID[provider] else {
      preconditionFailure("Missing QuotaFloat provider definition for \(provider.rawValue)")
    }
    return definition
  }

  static var orderedProviders: [QuotaProvider] {
    Self.definitions.map(\.id)
  }
}

extension QuotaProvider {
  var definition: QuotaProviderDefinition {
    QuotaProviderCatalog.definition(for: self)
  }
}
