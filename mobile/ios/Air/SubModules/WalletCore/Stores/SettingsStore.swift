import Dependencies
import Foundation
import GRDB
import WalletContext

private let log = Log("SettingsStore")

private func makeAuthConfigJson(kind: String) -> String? {
    let value = AnyCodable.dictionary([
        "kind": .string(kind),
    ])
    guard let data = try? JSONEncoder().encode(value) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

public final class SettingsStore: Sendable {
    private let _row: UnfairLock<MSettings> = .init(initialState: .init())
    private let _db: UnfairLock<(any DatabaseWriter)?> = .init(initialState: nil)

    init() {}

    func use(db: any DatabaseWriter) {
        _db.withLock { $0 = db }
        loadFromDb()
    }

    func clean() {
        _db.withLock { $0 = nil }
        _row.withLock { $0 = .init() }
    }

    public var theme: NightMode {
        NightMode(rawValue: _row.withLock { $0.theme }) ?? .system
    }

    public func setTheme(_ theme: NightMode) {
        update {
            $0.theme = theme.rawValue
        }
    }

    public var areAnimationsDisabled: Bool {
        _row.withLock { $0.areAnimationsDisabled }
    }

    public func setAreAnimationsDisabled(_ areAnimationsDisabled: Bool) {
        update {
            $0.areAnimationsDisabled = areAnimationsDisabled
        }
    }

    public var isSeasonalThemingDisabled: Bool {
        _row.withLock { $0.isSeasonalThemingDisabled }
    }

    public func setIsSeasonalThemingDisabled(_ isDisabled: Bool) {
        update {
            $0.isSeasonalThemingDisabled = isDisabled
        }
    }

    public var canPlaySounds: Bool {
        _row.withLock { $0.canPlaySounds }
    }

    public func setCanPlaySounds(_ canPlaySounds: Bool) {
        update {
            $0.canPlaySounds = canPlaySounds
        }
    }

    public var areTinyTransfersHidden: Bool {
        _row.withLock { $0.areTinyTransfersHidden }
    }

    public func setAreTinyTransfersHidden(_ areTinyTransfersHidden: Bool) {
        update {
            $0.areTinyTransfersHidden = areTinyTransfersHidden
        }
    }

    public var areTokensWithNoCostHidden: Bool {
        _row.withLock { $0.areTokensWithNoCostHidden }
    }

    public func setAreTokensWithNoCostHidden(_ areTokensWithNoCostHidden: Bool) {
        update {
            $0.areTokensWithNoCostHidden = areTokensWithNoCostHidden
        }
    }

    public var authConfigJson: String? {
        _row.withLock { $0.authConfig }
    }

    public var isBiometricActivated: Bool {
        _row.withLock { $0.authConfigKind == "native-biometrics" }
    }

    public func setIsBiometricActivated(_ isBiometricActivated: Bool) {
        update {
            $0.authConfig = makeAuthConfigJson(kind: isBiometricActivated ? "native-biometrics" : "password")
        }
    }

    public var autolockOption: MAutolockOption {
        guard
            let option = MAutolockOption(rawValue: _row.withLock({ $0.autolockValue }))
        else {
            return DEFAULT_AUTOLOCK_OPTION
        }
        return option
    }

    public func setAutolockOption(_ option: MAutolockOption) {
        update {
            $0.autolockValue = option.rawValue
        }
    }

    public var isSensitiveDataHidden: Bool {
        _row.withLock { $0.isSensitiveDataHidden }
    }

    public func setIsSensitiveDataHidden(_ isHidden: Bool) {
        update {
            $0.isSensitiveDataHidden = isHidden
        }
    }

    public var selectedExplorerIds: [String: String] {
        _row.withLock { $0.selectedExplorerIds }
    }

    public func selectedExplorerId(for chain: ApiChain) -> String? {
        selectedExplorerIds[chain.rawValue]
    }

    public func setSelectedExplorerId(_ explorerId: String, for chain: ApiChain) {
        update {
            var selectedExplorerIds = $0.selectedExplorerIds
            selectedExplorerIds[chain.rawValue] = explorerId
            $0.selectedExplorerIds = selectedExplorerIds
        }
    }

    public var isTokenChartExpanded: Bool {
        _row.withLock { $0.isTokenChartExpanded }
    }

    public func setIsTokenChartExpanded(_ isExpanded: Bool) {
        update {
            $0.isTokenChartExpanded = isExpanded
        }
    }

    public var pushNotifications: GlobalPushNotifications? {
        _row.withLock { $0.pushNotifications }
    }

    public func setPushNotifications(_ pushNotifications: GlobalPushNotifications?) {
        update {
            $0.pushNotifications = pushNotifications
        }
    }

    public var currentTokenPeriod: String {
        _row.withLock { $0.currentTokenPeriod }
    }

    public func setCurrentTokenPeriod(_ currentTokenPeriod: String) {
        update {
            $0.currentTokenPeriod = currentTokenPeriod
        }
    }

    public var homeWalletVisibleTokensLimit: HomeWalletVisibleTokensLimit {
        HomeWalletVisibleTokensLimit(storedValue: _row.withLock { $0.walletTokensLimit })
    }

    public func setHomeWalletVisibleTokensLimit(_ limit: HomeWalletVisibleTokensLimit) {
        update {
            $0.walletTokensLimit = limit.rawValue
        }
    }

    private func update(_ mutate: (inout MSettings) -> Void) {
        var row = _row.withLock { $0 }
        let oldRow = row
        mutate(&row)
        guard row != oldRow else { return }
        let nextRow = row
        _row.withLock { $0 = nextRow }
        persist(nextRow)
    }

    private func persist(_ row: MSettings) {
        guard let db = _db.withLock({ $0 }) else {
            assertionFailure("database not ready")
            return
        }

        do {
            try db.write { db in
                try row.upsert(db)
            }
        } catch {
            log.error("persist failed error=\(error, .public)")
        }
    }

    private func loadFromDb() {
        do {
            guard let db = _db.withLock({ $0 }) else {
                assertionFailure("database not ready")
                return
            }
            let row = try db.read { db in
                try MSettings.fetchOne(db, key: SINGLETON_TABLE_ROW_ID)
            } ?? .init()
            try db.write { db in
                try row.upsert(db)
            }
            _row.withLock { $0 = row }
        } catch {
            log.error("initial load failed: \(error, .public)")
        }
    }
}

extension SettingsStore: DependencyKey {
    public static let liveValue: SettingsStore = SettingsStore()
}

public extension DependencyValues {
    var settingsStore: SettingsStore {
        get { self[SettingsStore.self] }
        set { self[SettingsStore.self] = newValue }
    }
}
