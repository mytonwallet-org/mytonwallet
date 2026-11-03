import Foundation

struct PerpsCachedChart: Codable, Sendable {
    var points: [[Double]]
    var fetchedAt: Date

    static func boundedPoints(_ points: [[Double]]) -> [[Double]] {
        let limit = PerpsCachedAccount.chartPointLimit
        guard points.count > limit else { return points }
        return (0..<limit).map { points[$0 * (points.count - 1) / (limit - 1)] }
    }
}

struct PerpsCachedAccount: Codable, Sendable {
    static let historyLimit = 200
    static let chartLimit = 24
    static let chartPointLimit = 2_000

    var snapshot: ApiPerpsSnapshot?
    var snapshotFetchedAt: Date?
    var history: ApiPerpsActivityHistory?
    var historyFetchedAt: Date?
    var hasActivityHistory: Bool?
    var charts: [String: PerpsCachedChart]?

    func sanitized(now: Date) -> Self? {
        var value = self
        if snapshot?.positions.isEmpty == false || history?.hasActivity == true || history?.fills.isEmpty == false || history?.cashFlows.isEmpty == false {
            value.hasActivityHistory = true
        }
        if let date = snapshotFetchedAt, date > now { value.snapshotFetchedAt = now }
        if let date = historyFetchedAt, date > now { value.historyFetchedAt = now }
        if let history = value.history {
            var seen = Set<String>()
            value.history = .init(
                fills: Array(history.fills.filter { seen.insert($0.id).inserted }.prefix(Self.historyLimit)),
                cashFlows: Array(history.cashFlows.filter { $0.kind != .funding && seen.insert($0.id).inserted }.prefix(Self.historyLimit))
            )
        }
        if let charts = value.charts {
            value.charts = Dictionary(uniqueKeysWithValues: charts
                .filter { $0.value.points.allSatisfy { point in
                    point.count == 2 && point.allSatisfy { $0.isFinite && $0 > 0 }
                } }
                .sorted { $0.value.fetchedAt > $1.value.fetchedAt }
                .prefix(Self.chartLimit)
                .map { ($0.key, PerpsCachedChart(points: PerpsCachedChart.boundedPoints($0.value.points), fetchedAt: $0.value.fetchedAt)) })
        }
        return value.snapshot == nil && value.history == nil && (value.charts?.isEmpty ?? true) ? nil : value
    }
}

/// Persistent display data. Quotes and execution state are never restored from this cache.
final class PerpsReadCache: Sendable {
    private struct Contents: Codable {
        var version = 3
        var accounts: [String: PerpsCachedAccount]
    }

    private static let byteLimit = 32 * 1024 * 1024
    private let url: URL
    private let legacyURL: URL?
    private let queue = DispatchQueue(label: "org.mytonwallet.perps-read-cache", qos: .utility)

    init(url: URL, legacyURL: URL? = nil) {
        self.url = url
        self.legacyURL = legacyURL
    }

    func load() async -> [String: PerpsCachedAccount] {
        await withCheckedContinuation { continuation in
            queue.async { [url, legacyURL] in
                for source in [url, legacyURL].compactMap({ $0 }) {
                    guard let attributes = try? FileManager.default.attributesOfItem(atPath: source.path()),
                          let size = attributes[.size] as? NSNumber, size.intValue <= Self.byteLimit,
                          let data = try? Data(contentsOf: source) else { continue }
                    do {
                        let contents = try JSONDecoder().decode(Contents.self, from: data)
                        guard [2, 3].contains(contents.version) else { throw CocoaError(.coderReadCorrupt) }
                        continuation.resume(returning: contents.accounts)
                        return
                    } catch {
                        try? FileManager.default.removeItem(at: source)
                    }
                }
                continuation.resume(returning: [:])
            }
        }
    }

    func save(_ accounts: [String: PerpsCachedAccount]) {
            queue.async { [url, legacyURL] in
            guard !accounts.isEmpty else {
                try? FileManager.default.removeItem(at: url)
                if let legacyURL { try? FileManager.default.removeItem(at: legacyURL) }
                return
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(Contents(accounts: accounts))
                guard data.count <= Self.byteLimit else { return }
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var storedURL = url
                var resources = URLResourceValues()
                resources.isExcludedFromBackup = true
                try storedURL.setResourceValues(resources)
                if let legacyURL { try? FileManager.default.removeItem(at: legacyURL) }
            } catch {
                // Preserve the last complete file if a display-cache write fails.
            }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}
