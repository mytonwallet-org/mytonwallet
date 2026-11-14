import Foundation
import os
import StoreKit
import Testing
@testable import WalletCore

private let installedAt = Date(timeIntervalSince1970: 1_791_600_000.789)
private let purchasedAt = Date(timeIntervalSince1970: 1_700_000_000.123)

@Suite @MainActor
struct AppInstallationStoreTests {

    @Test func firstReadingBecomesOneEventOfANewInstallation() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = self.store(directory, reading: .transaction(isVerified: true, originalPurchaseDate: purchasedAt, environment: "production"))

        #expect(await store.collectIfNeeded())
        let deliveries = store.pendingDeliveries()
        #expect(deliveries.count == 1)
        #expect(deliveries.first?["slot"] as? String == "app_transaction")
        let body = try #require(deliveries.first?["body"] as? [String: Any])
        #expect(Set(body.keys) == ["schemaVersion", "installationId", "eventId", "sourceTransport", "packageInstalledAt",
                                   "collectionStatus", "originalPurchasedAt", "storeEnvironment"])
        #expect(body["schemaVersion"] as? Int == 2)
        #expect(body["installationId"] as? String == uuid(1))
        #expect(body["eventId"] as? String == uuid(2))
        #expect(body["sourceTransport"] as? String == "app_transaction")
        #expect(body["packageInstalledAt"] as? Int64 == 1_791_600_000_789)
        #expect(body["collectionStatus"] as? String == "ok")
        #expect(body["originalPurchasedAt"] as? Int64 == 1_700_000_000_123)
        #expect(body["storeEnvironment"] as? String == "production")
        let record = directory.appending(component: "installation.json")
        #expect(try record.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func onlyTheExactAnswerForThePendingEventSettlesIt() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = self.store(directory, reading: .transaction(isVerified: false, originalPurchaseDate: purchasedAt, environment: "sandbox"))
        #expect(await store.collectIfNeeded())
        let answer: [String: Any] = ["ok": true, "schemaVersion": 2, "installationId": uuid(1), "eventId": uuid(2)]

        for wrong in [answer.merging(["ok": false]) { $1 }, answer.merging(["eventId": uuid(9)]) { $1 },
                      answer.merging(["installationId": uuid(9)]) { $1 }, answer.merging(["schemaVersion": 1]) { $1 }] {
            let wrongJSON = try json(wrong)
            #expect(!store.acknowledge(slot: "app_transaction", acknowledgementJSON: wrongJSON))
        }
        let answerJSON = try json(answer)
        #expect(!store.acknowledge(slot: "play", acknowledgementJSON: answerJSON))
        #expect(!store.acknowledge(slot: "app_transaction", acknowledgementJSON: "not json"))
        #expect(store.pendingDeliveries().count == 1)
        #expect((store.pendingDeliveries().first?["body"] as? [String: Any])?["collectionStatus"] as? String == "unverified")

        #expect(store.acknowledge(slot: "app_transaction", acknowledgementJSON: answerJSON))
        #expect(store.pendingDeliveries().isEmpty)
        let relaunched = self.store(directory, reading: .failed, firstUUID: 10)
        #expect(relaunched.pendingDeliveries().isEmpty)
        #expect(!(await relaunched.collectIfNeeded()))
        #expect(relaunched.reads.withLock { $0 } == 0)
    }

    @Test func aFailureIsReportedOnceAndALaterLaunchReplacesItWithTheTransaction() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = store(directory, reading: .failed)
        #expect(await first.collectIfNeeded())
        #expect(!(await first.collectIfNeeded()))
        #expect(first.reads.withLock { $0 } == 1)
        let failed = try #require(first.pendingDeliveries().first?["body"] as? [String: Any])
        #expect(failed["collectionStatus"] as? String == "failed")
        #expect(failed["originalPurchasedAt"] is NSNull)
        #expect(failed["storeEnvironment"] as? String == "")
        #expect(failed["packageInstalledAt"] as? Int64 == 1_791_600_000_789)

        let stillFailing = store(directory, reading: .failed, firstUUID: 10)
        #expect(!(await stillFailing.collectIfNeeded()))
        #expect((stillFailing.pendingDeliveries().first?["body"] as? [String: Any])?["eventId"] as? String == uuid(2))

        let recovered = store(
            directory,
            reading: .transaction(isVerified: true, originalPurchaseDate: purchasedAt, environment: "production"),
            firstUUID: 20
        )
        #expect(await recovered.collectIfNeeded())
        let settled = try #require(recovered.pendingDeliveries().first?["body"] as? [String: Any])
        #expect(settled["installationId"] as? String == uuid(1))
        #expect(settled["eventId"] as? String == uuid(20))
        #expect(settled["collectionStatus"] as? String == "ok")
        #expect(settled["packageInstalledAt"] as? Int64 == 1_791_600_000_789)
        #expect(!(await store(directory, reading: .failed, firstUUID: 30).collectIfNeeded()))
    }

    @Test func anUnavailableTransactionIsFinal() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = self.store(directory, reading: .unavailable, containerDate: nil)
        #expect(await store.collectIfNeeded())
        let body = try #require(store.pendingDeliveries().first?["body"] as? [String: Any])
        #expect(body["collectionStatus"] as? String == "unavailable")
        #expect(body["packageInstalledAt"] is NSNull)
        #expect(body["originalPurchasedAt"] is NSNull)
        let relaunched = self.store(directory, reading: .failed, firstUUID: 10)
        #expect(!(await relaunched.collectIfNeeded()))
        #expect(relaunched.reads.withLock { $0 } == 0)
    }

    @Test func anUnreadableRecordNeverBecomesASecondInstallation() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = directory.appending(component: "installation.json")
        try Data("damaged".utf8).write(to: record)
        let store = self.store(directory, reading: .unavailable)

        #expect(store.pendingDeliveries().isEmpty)
        #expect(!(await store.collectIfNeeded()))
        #expect(store.reads.withLock { $0 } == 0)
        #expect(try Data(contentsOf: record) == Data("damaged".utf8))
    }

    @Test func storeKitRefusalsThatCannotChangeAreFinalAndTheRestAreRetried() {
        #expect(AppInstallationStore.reading(for: StoreKitError.notAvailableInStorefront) == .unavailable)
        #expect(AppInstallationStore.reading(for: StoreKitError.notEntitled) == .unavailable)
        #expect(AppInstallationStore.reading(for: StoreKitError.networkError(URLError(.notConnectedToInternet))) == .failed)
        #expect(AppInstallationStore.reading(for: StoreKitError.unknown) == .failed)
        #expect(AppInstallationStore.reading(for: CocoaError(.fileReadUnknown)) == .failed)
    }

    @Test func storeEnvironmentsAreTheLowercaseNamesTheBackendStores() {
        #expect(AppInstallationStore.storeEnvironment(.production) == "production")
        #expect(AppInstallationStore.storeEnvironment(.sandbox) == "sandbox")
        #expect(AppInstallationStore.storeEnvironment(.xcode) == "xcode")
    }

    // MARK: - Helpers

    private func store(
        _ directory: URL,
        reading: AppTransactionReading,
        containerDate: Date? = installedAt,
        firstUUID: Int = 1
    ) -> CountingStore {
        CountingStore(
            fileURL: directory.appending(component: "installation.json"),
            reading: reading,
            containerDate: containerDate,
            firstUUID: firstUUID
        )
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(component: "AppInstallationStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
}

private func uuid(_ index: Int) -> String {
    String(format: "00000000-0000-4000-8000-%012d", index)
}

@MainActor
private final class CountingStore {
    let reads: OSAllocatedUnfairLock<Int>
    private let store: AppInstallationStore

    init(fileURL: URL, reading: AppTransactionReading, containerDate: Date?, firstUUID: Int) {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        self.reads = reads
        var next = firstUUID - 1
        store = AppInstallationStore(
            fileURL: fileURL,
            readTransaction: {
                reads.withLock { $0 += 1 }
                return reading
            },
            containerCreationDate: { containerDate },
            makeUUID: {
                next += 1
                return UUID(uuidString: uuid(next))!
            }
        )
    }

    func collectIfNeeded() async -> Bool { await store.collectIfNeeded() }
    func pendingDeliveries() -> [[String: Any]] { store.pendingDeliveries() }
    func acknowledge(slot: String, acknowledgementJSON: String) -> Bool {
        store.acknowledge(slot: slot, acknowledgementJSON: acknowledgementJSON)
    }
}
