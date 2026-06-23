import Foundation

final class QuotaCacheStore {
  let fileURL: URL

  init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
      return
    }

    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
    self.fileURL =
      support
      .appendingPathComponent("QuotaFloat", isDirectory: true)
      .appendingPathComponent("quota-cache.json", isDirectory: false)
  }

  func load() -> [QuotaSnapshot] {
    guard let data = try? Data(contentsOf: self.fileURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let cache = try? decoder.decode(QuotaCache.self, from: data), cache.version == 1 else {
      return []
    }
    return cache.snapshots.filter(\.hasQuotaData)
  }

  func save(_ snapshots: [QuotaSnapshot]) {
    let persistentSnapshots = snapshots.filter(\.hasQuotaData)
    guard !persistentSnapshots.isEmpty else { return }

    do {
      try FileManager.default.createDirectory(
        at: self.fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(QuotaCache(snapshots: persistentSnapshots))
      try data.write(to: self.fileURL, options: .atomic)
    } catch {
      // Cache failures must never interrupt live quota display.
    }
  }
}
