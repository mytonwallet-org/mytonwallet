import Foundation

struct PerpsCachedChart: Codable, Sendable, Equatable {
    static let limit = 24
    static let pointLimit = 2_000

    var points: [[Double]]
    var fetchedAt: Date

    static func boundedPoints(_ points: [[Double]]) -> [[Double]] {
        guard points.count > pointLimit else { return points }
        return (0..<pointLimit).map { points[$0 * (points.count - 1) / (pointLimit - 1)] }
    }

    static func isValid(_ points: [[Double]]) -> Bool {
        points.allSatisfy { $0.count == 2 && $0.allSatisfy { $0.isFinite && $0 > 0 } }
    }

    /// The most recently read charts with valid points, each bounded to `pointLimit`.
    static func bounded(_ charts: [String: PerpsCachedChart]) -> [String: PerpsCachedChart] {
        Dictionary(uniqueKeysWithValues: charts
            .filter { isValid($0.value.points) }
            .sorted { $0.value.fetchedAt > $1.value.fetchedAt }
            .prefix(limit)
            .map { ($0.key, PerpsCachedChart(points: boundedPoints($0.value.points), fetchedAt: $0.value.fetchedAt)) })
    }
}

/// One account's positions and recent Activity.
struct PerpsCachedAccount: Codable, Sendable, Equatable {
    static let historyLimit = 200

    var snapshot: ApiPerpsAccountSnapshot?
    var fills: [ApiPerpsFill]?
    var historyFetchedAt: Date?
    var hasActivityHistory: Bool?

    func sanitized() -> Self? {
        var value = self
        if let fills {
            var seen = Set<String>()
            value.fills = Array(fills.filter { seen.insert($0.id).inserted }.prefix(Self.historyLimit))
        }
        return value.snapshot == nil && value.fills == nil && value.hasActivityHistory == nil ? nil : value
    }
}

/// The catalogue shared by all accounts, in the language it was read in.
struct PerpsCachedMarket: Codable, Sendable, Equatable {
    var langCode: String
    var market: ApiPerpsMarketSnapshot
    /// Descriptions read with asset details; the catalogue carries them only for featured assets.
    var descriptions: [String: String]
}

/// Persistent display data. Quotes and execution state are never restored from it.
/// Account data is loaded before the first layout; charts are read when an asset page first needs them.
struct PerpsReadCache: Sendable {
    static let accountsVersion = 1
    static let marketVersion = 1
    static let chartsVersion = 1

    let accounts: PerpsFileCache<[String: PerpsCachedAccount]>
    let market: PerpsFileCache<PerpsCachedMarket>
    let charts: PerpsFileCache<[String: PerpsCachedChart]>

    init(directory: URL) {
        accounts = .init(url: directory.appending(component: "accounts.json"), version: Self.accountsVersion)
        market = .init(url: directory.appending(component: "market.json"), version: Self.marketVersion)
        charts = .init(url: directory.appending(component: "charts.json"), version: Self.chartsVersion)
    }

    func flush() async {
        await accounts.flush()
        await market.flush()
        await charts.flush()
    }
}

/// A versioned JSON file read and written on a background queue in the order requested,
/// so a read sees every save requested before it and none requested after it.
final class PerpsFileCache<Contents: Codable & Sendable>: Sendable {
    private struct Envelope: Codable {
        var version: Int
        var contents: Contents
    }

    let url: URL
    private let version: Int
    private let queue: DispatchQueue

    init(url: URL, version: Int) {
        self.url = url
        self.version = version
        queue = DispatchQueue(label: "org.mytonwallet.perps-cache." + url.lastPathComponent, qos: .utility)
    }

    /// Queues the read at once; the task returns the contents. A file in another format is removed.
    func load() -> Task<Contents?, Never> {
        let contents = AsyncStream<Contents?>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            queue.async { [self] in
                continuation.yield(read())
                continuation.finish()
            }
        }
        return Task {
            for await value in contents { return value }
            return nil
        }
    }

    /// Saving nil removes the file.
    func save(_ contents: Contents?) {
        queue.async { [self] in store(contents) }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func read() -> Contents? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.version == version else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return envelope.contents
    }

    private func store(_ contents: Contents?) {
        guard let contents else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Envelope(version: version, contents: contents))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var storedURL = url
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try storedURL.setResourceValues(resources)
        } catch {
            // Keep the last complete file if a display-cache write fails.
        }
    }
}
