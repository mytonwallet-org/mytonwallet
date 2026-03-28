import Foundation
import GRDB
import WalletContext

private let log = Log("DatabaseBootstrap")

public enum StartupLegacyAccountsState: String, Sendable {
    case absent
    case present
    case unknown
}

public struct StartupWalletEvidence: Sendable {
    public let databaseAccountCount: Int
    public let keychainAccountCount: Int
    public let legacyAccountsState: StartupLegacyAccountsState

    public init(
        databaseAccountCount: Int,
        keychainAccountCount: Int,
        legacyAccountsState: StartupLegacyAccountsState
    ) {
        self.databaseAccountCount = databaseAccountCount
        self.keychainAccountCount = keychainAccountCount
        self.legacyAccountsState = legacyAccountsState
    }

    public var canContinueWithoutBlockingLegacyFailure: Bool {
        if databaseAccountCount > 0 {
            return true
        }
        switch legacyAccountsState {
        case .absent:
            return true
        case .present:
            return false
        case .unknown:
            return keychainAccountCount == 0
        }
    }

    public var shouldDeletePreviousInstallAccountsOnFirstLaunch: Bool {
        databaseAccountCount == 0 && keychainAccountCount > 0 && legacyAccountsState == .absent
    }

    public var traceDetails: String {
        "db=\(databaseAccountCount) keychain=\(keychainAccountCount) legacy=\(legacyAccountsState.rawValue)"
    }

    public func updating(
        databaseAccountCount: Int? = nil,
        legacyAccountsState: StartupLegacyAccountsState? = nil
    ) -> StartupWalletEvidence {
        StartupWalletEvidence(
            databaseAccountCount: databaseAccountCount ?? self.databaseAccountCount,
            keychainAccountCount: keychainAccountCount,
            legacyAccountsState: legacyAccountsState ?? self.legacyAccountsState
        )
    }
}

public struct DatabaseBootstrapResult {
    public let db: any DatabaseWriter
    public let walletEvidence: StartupWalletEvidence

    public init(db: any DatabaseWriter, walletEvidence: StartupWalletEvidence) {
        self.db = db
        self.walletEvidence = walletEvidence
    }

    public var databaseAccountCount: Int {
        walletEvidence.databaseAccountCount
    }

    public var shouldDeletePreviousInstallAccountsOnFirstLaunch: Bool {
        walletEvidence.shouldDeletePreviousInstallAccountsOnFirstLaunch
    }
}

public enum DatabaseBootstrap {
    private static let requiredLegacyMigrationIds = Set([
        legacyAssetsAndActivityMigrationId,
        legacyStorageMigrationId,
    ])

    public static func prepare() async throws -> DatabaseBootstrapResult {
        log.info("prepare")
        StartupTrace.mark("airLauncher.database.connect.begin")
        let db = try connectToDatabase()
        StartupTrace.mark("airLauncher.database.connect.end")
        let initialDatabaseAccountCount = try await fetchDatabaseAccountCount(db: db)
        var walletEvidence = StartupWalletEvidence(
            databaseAccountCount: initialDatabaseAccountCount,
            keychainAccountCount: KeychainHelper.getAccounts()?.count ?? 0,
            legacyAccountsState: .unknown
        )
        StartupTrace.mark("airLauncher.walletEvidence.ready", details: walletEvidence.traceDetails)
        walletEvidence = try await bootstrapLegacyStorageIfNeeded(db: db, walletEvidence: walletEvidence)
        let databaseAccountCount = try await fetchDatabaseAccountCount(db: db)
        walletEvidence = walletEvidence.updating(databaseAccountCount: databaseAccountCount)
        StartupTrace.mark("airLauncher.database.accountCount.ready", details: walletEvidence.traceDetails)
        return DatabaseBootstrapResult(
            db: db,
            walletEvidence: walletEvidence
        )
    }

    @MainActor
    public static func exportStateToCapacitor(db: any DatabaseWriter) async throws {
        let migrationGlobalStorage = GlobalStorage()
        do {
            try await migrationGlobalStorage.loadFromWebView()
            try await migrationGlobalStorage.migrate()
        } catch {
            log.error("failed to load existing global storage before switch: \(error, .public)")
            migrationGlobalStorage.update {
                $0["stateVersion"] = STATE_VERSION
            }
        }
        try await switchStorageToCapacitor(global: migrationGlobalStorage, db: db)
    }

    @MainActor
    private static func bootstrapLegacyStorageIfNeeded(
        db: any DatabaseWriter,
        walletEvidence initialWalletEvidence: StartupWalletEvidence
    ) async throws -> StartupWalletEvidence {
        var walletEvidence = initialWalletEvidence
        let needsLegacyBootstrap: Bool
        do {
            needsLegacyBootstrap = try await shouldBootstrapGlobalStorage(db: db)
        } catch {
            if walletEvidence.canContinueWithoutBlockingLegacyFailure {
                log.fault("failed to decide whether legacy bootstrap is needed: \(error, .public). will continue without blocking startup")
                StartupTrace.mark(
                    "airLauncher.globalStorage.bootstrapDecision.failed",
                    details: "continuingWithoutLegacyBootstrap=true \(walletEvidence.traceDetails)"
                )
                StartupTrace.mark("airLauncher.globalStorage.load.skipped")
                StartupTrace.mark("airLauncher.storage.switchFromCapacitor.skipped")
                StartupTrace.mark("airLauncher.legacyMigration.skipped")
                return walletEvidence.updating(legacyAccountsState: .unknown)
            }
            throw error
        }
        StartupTrace.mark("airLauncher.globalStorage.bootstrapDecision", details: "shouldLoad=\(needsLegacyBootstrap)")
        guard needsLegacyBootstrap else {
            StartupTrace.mark("airLauncher.globalStorage.load.skipped")
            StartupTrace.mark("airLauncher.storage.switchFromCapacitor.skipped")
            StartupTrace.mark("airLauncher.legacyMigration.skipped")
            return walletEvidence.updating(legacyAccountsState: .absent)
        }

        let storage = GlobalStorage()
        StartupTrace.mark("airLauncher.globalStorage.load.begin")
        do {
            try await storage.loadFromWebView()
            StartupTrace.mark("airLauncher.globalStorage.load.end")
        } catch GlobalStorageError.localStorageIsNull, GlobalStorageError.localStorageIsEmpty {
            storage.update { $0[""] = [:] }
            LocalizationSupport.shared.migrateLanguageFromGlobalStorageIfNeeded(global: storage)
            StartupTrace.mark("airLauncher.languageMigration.end")
            StartupTrace.mark("airLauncher.globalStorage.load.empty")
            await markLegacyBootstrapNotNeededIfPossible(db: db)
            StartupTrace.mark("airLauncher.storage.switchFromCapacitor.skipped")
            StartupTrace.mark("airLauncher.legacyMigration.skipped")
            return walletEvidence.updating(legacyAccountsState: .absent)
        } catch {
            if walletEvidence.canContinueWithoutBlockingLegacyFailure {
                log.fault("failed to load global storage: \(error, .public). will continue without blocking startup")
                StartupTrace.mark(
                    "airLauncher.globalStorage.load.failed",
                    details: "continuingWithoutLegacyBootstrap=true \(walletEvidence.traceDetails)"
                )
                StartupTrace.mark("airLauncher.storage.switchFromCapacitor.skipped")
                StartupTrace.mark("airLauncher.legacyMigration.skipped")
                return walletEvidence.updating(legacyAccountsState: .unknown)
            }
            throw error
        }

        walletEvidence = walletEvidence.updating(legacyAccountsState: detectLegacyAccountsState(in: storage))

        do {
            StartupTrace.mark("airLauncher.globalStorage.migrate.begin")
            try await storage.migrate()
            StartupTrace.mark("airLauncher.globalStorage.migrate.end")
        } catch {
            let migratedInMemory = (storage["stateVersion"] as? Int) == STATE_VERSION
            if migratedInMemory {
                log.fault("failed to persist migrated global storage: \(error, .public). will continue with in-memory migrated state")
                StartupTrace.mark("airLauncher.globalStorage.migrate.failed", details: "continuingWithInMemoryState=true")
            } else if walletEvidence.canContinueWithoutBlockingLegacyFailure {
                log.fault("failed to initialize global storage: \(error, .public). will continue without blocking startup")
                StartupTrace.mark(
                    "airLauncher.globalStorage.init.failed",
                    details: "continuingWithoutLegacyBootstrap=true \(walletEvidence.traceDetails)"
                )
                StartupTrace.mark("airLauncher.storage.switchFromCapacitor.skipped")
                StartupTrace.mark("airLauncher.legacyMigration.skipped")
                return walletEvidence
            } else {
                throw error
            }
        }

        LocalizationSupport.shared.migrateLanguageFromGlobalStorageIfNeeded(global: storage)
        StartupTrace.mark("airLauncher.languageMigration.end")
        walletEvidence = walletEvidence.updating(legacyAccountsState: detectLegacyAccountsState(in: storage))

        do {
            try await switchStorageFromCapacitorIfNeeded(global: storage, db: db)
        } catch {
            log.fault("failed to import legacy storage into database: \(error, .public). will block startup to avoid partial migration state")
            StartupTrace.mark(
                "airLauncher.storage.switchFromCapacitor.failed",
                details: "blockingStartup=true \(walletEvidence.traceDetails) error=\(String(reflecting: error))"
            )
            throw error
        }
        StartupTrace.mark("airLauncher.storage.switchFromCapacitor.end")

        do {
            try await migrateLegacyAssetsAndActivityDataIfNeeded(global: storage, db: db)
            StartupTrace.mark("airLauncher.legacyAssetsAndActivityMigration.end")
        } catch {
            log.fault("failed to migrate legacy assets/activity data: \(error, .public)")
            StartupTrace.mark("airLauncher.legacyAssetsAndActivityMigration.failed")
            assertionFailure("failed to migrate legacy assets/activity data: \(error)")
        }

        await migrateLegacyStorageIfNeeded(global: storage, db: db)

        return walletEvidence
    }

    private static func shouldBootstrapGlobalStorage(db: any DatabaseWriter) async throws -> Bool {
        let switchedFromCapacitorDate = try await db.read { db in
            try Date.fetchOne(db, sql: "SELECT switched_from_capacitor_dt FROM common")
        }
        if switchedFromCapacitorDate == nil {
            return true
        }

        let executedMigrationIds = Set(try await db.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM one_time_migrations")
        })

        return !requiredLegacyMigrationIds.isSubset(of: executedMigrationIds)
            || LocalizationSupport.shared.needsLegacyGlobalStorageMigration
    }

    private static func markLegacyBootstrapNotNeeded(db: any DatabaseWriter) async throws {
        try await db.write { db in
            for migrationId in requiredLegacyMigrationIds {
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO one_time_migrations (id, executedAt)
                    VALUES (?, CURRENT_TIMESTAMP)
                    """,
                    arguments: [migrationId]
                )
            }
            try db.execute(
                sql: """
                UPDATE common
                SET switched_from_capacitor_dt = COALESCE(switched_from_capacitor_dt, CURRENT_TIMESTAMP)
                """
            )
        }
    }

    private static func markLegacyBootstrapNotNeededIfPossible(db: any DatabaseWriter) async {
        do {
            try await markLegacyBootstrapNotNeeded(db: db)
        } catch {
            log.fault("failed to mark legacy bootstrap as not needed: \(error, .public)")
            StartupTrace.mark("airLauncher.globalStorage.bootstrapMark.failed", details: String(reflecting: error))
        }
    }

    private static func fetchDatabaseAccountCount(db: any DatabaseWriter) async throws -> Int {
        try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accounts") ?? 0
        }
    }

    @MainActor
    private static func detectLegacyAccountsState(in storage: GlobalStorage) -> StartupLegacyAccountsState {
        storage.keysIn(key: "accounts")?.isEmpty == false ? .present : .absent
    }
}
