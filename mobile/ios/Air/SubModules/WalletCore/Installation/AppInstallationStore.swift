import Foundation
import StoreKit
import WalletContext

private let log = Log("AppInstallationStore")

enum AppTransactionReading: Equatable, Sendable {
    case transaction(isVerified: Bool, originalPurchaseDate: Date, environment: String)
    case unavailable
    case failed
}

/// One app-data instance: its installation ID and the App Store transaction event the SDK has yet to deliver.
/// Kept out of the backup, so a restored or transferred device starts a new installation.
@MainActor
final class AppInstallationStore {
    static let slot = "app_transaction"
    static let shared = AppInstallationStore(
        fileURL: URL.applicationSupportDirectory.appending(components: "air", "installation.json"),
        readTransaction: { await readAppTransaction() },
        containerCreationDate: { documentsCreationDate() },
        makeUUID: { UUID() }
    )

    struct Record: Codable, Equatable {
        var installationId: String
        var packageInstalledAt: Int64?
        var isCollected = false
        var hasReportedFailure = false
        var pending: Event?
    }

    struct Event: Codable, Equatable {
        var eventId: String
        var collectionStatus: String
        var originalPurchasedAt: Int64?
        var storeEnvironment: String
    }

    private let fileURL: URL
    private let readTransaction: @Sendable () async -> AppTransactionReading
    private let containerCreationDate: () -> Date?
    private let makeUUID: () -> UUID
    private var record: Record?
    private var hasAttemptedCollection = false

    init(
        fileURL: URL,
        readTransaction: @escaping @Sendable () async -> AppTransactionReading,
        containerCreationDate: @escaping () -> Date?,
        makeUUID: @escaping () -> UUID
    ) {
        self.fileURL = fileURL
        self.readTransaction = readTransaction
        self.containerCreationDate = containerCreationDate
        self.makeUUID = makeUUID
    }

    func pendingDeliveries() -> [[String: Any]] {
        guard let record = loadRecord(), let event = record.pending else { return [] }
        let body: [String: Any] = [
            "schemaVersion": 2,
            "installationId": record.installationId,
            "eventId": event.eventId,
            "sourceTransport": Self.slot,
            "packageInstalledAt": record.packageInstalledAt.map { $0 as Any } ?? NSNull(),
            "collectionStatus": event.collectionStatus,
            "originalPurchasedAt": event.originalPurchasedAt.map { $0 as Any } ?? NSNull(),
            "storeEnvironment": event.storeEnvironment,
        ]
        return [["slot": Self.slot, "body": body]]
    }

    /// Settles the pending event only on the backend's exact answer for it; anything else leaves it for a resend.
    func acknowledge(slot: String, acknowledgementJSON: String) -> Bool {
        guard slot == Self.slot, var updated = loadRecord(), let event = updated.pending,
              let data = acknowledgementJSON.data(using: .utf8),
              let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              answer["ok"] as? Bool == true, answer["schemaVersion"] as? Int == 2,
              answer["installationId"] as? String == updated.installationId,
              answer["eventId"] as? String == event.eventId else { return false }
        updated.pending = nil
        return save(updated)
    }

    /// Reads the app transaction at most once per process until a reading settles it; returns whether a new
    /// event awaits delivery. A failure is reported once, and a later launch replaces it with the settled reading.
    func collectIfNeeded() async -> Bool {
        guard !hasAttemptedCollection, let current = loadRecord(), !current.isCollected else { return false }
        hasAttemptedCollection = true
        let reading = await readTransaction()
        guard var updated = loadRecord(), !updated.isCollected else { return false }
        switch reading {
        case .transaction(let isVerified, let originalPurchaseDate, let environment):
            updated.isCollected = true
            updated.pending = Event(
                eventId: makeUUID().uuidString.lowercased(),
                collectionStatus: isVerified ? "ok" : "unverified",
                originalPurchasedAt: Self.milliseconds(originalPurchaseDate),
                storeEnvironment: environment
            )
        case .unavailable:
            updated.isCollected = true
            updated.pending = Event(
                eventId: makeUUID().uuidString.lowercased(), collectionStatus: "unavailable",
                originalPurchasedAt: nil, storeEnvironment: ""
            )
        case .failed:
            guard !updated.hasReportedFailure else { return false }
            updated.hasReportedFailure = true
            updated.pending = Event(
                eventId: makeUUID().uuidString.lowercased(), collectionStatus: "failed",
                originalPurchasedAt: nil, storeEnvironment: ""
            )
        }
        return save(updated)
    }

    // A record that exists but cannot be read (still protected before the first unlock, or damaged) yields nil
    // rather than a new identity, which would count this installation a second time.
    private func loadRecord() -> Record? {
        if let record { return record }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            do {
                record = try JSONDecoder().decode(Record.self, from: data)
            } catch {
                log.fault("installation record is unreadable: \(error, .public)")
            }
            return record
        }
        let created = Record(
            installationId: makeUUID().uuidString.lowercased(),
            packageInstalledAt: containerCreationDate().map(Self.milliseconds)
        )
        return save(created) ? created : nil
    }

    private func save(_ updated: Record) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var storedURL = fileURL
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try storedURL.setResourceValues(resources)
            record = updated
            return true
        } catch {
            log.error("installation record was not saved: \(error, .public)")
            return false
        }
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    static func storeEnvironment(_ environment: AppStore.Environment) -> String {
        environment.rawValue.lowercased()
    }

    static func reading(for error: Error) -> AppTransactionReading {
        guard let storeKitError = error as? StoreKitError else { return .failed }
        switch storeKitError {
        case .notAvailableInStorefront, .notEntitled:
            return .unavailable
        default:
            break
        }
        if #available(iOS 18.4, *), case .unsupported = storeKitError {
            return .unavailable
        }
        return .failed
    }

    // `AppTransaction.refresh()` would ask the person to sign in to the App Store, so only the cached read is used.
    private static func readAppTransaction() async -> AppTransactionReading {
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction):
                return .transaction(
                    isVerified: true,
                    originalPurchaseDate: transaction.originalPurchaseDate,
                    environment: storeEnvironment(transaction.environment)
                )
            case .unverified(let transaction, let error):
                log.error("app transaction is unverified: \(error, .public)")
                return .transaction(
                    isVerified: false,
                    originalPurchaseDate: transaction.originalPurchaseDate,
                    environment: storeEnvironment(transaction.environment)
                )
            }
        } catch {
            log.error("app transaction is not available: \(error, .public)")
            return reading(for: error)
        }
    }

    private static func documentsCreationDate() -> Date? {
        try? URL.documentsDirectory.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
}
