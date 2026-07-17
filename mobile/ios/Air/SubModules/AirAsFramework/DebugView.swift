
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import GRDB

private let log = Log("DebugView")


@MainActor func _showDebugView() {
    let vc = UIHostingController(rootView: DebugView())
    topViewController()?.present(vc, animated: true)
}


struct DebugView: View {
    
    @State private var showDeleteAllAlert: Bool = false
    @AppStorage("debug_displayLogOverlay") private var displayLogOverlayEnabled = false
    @AppStorage(DebugProductionMode.userDefaultsKey) private var forceProductionMode = false
    @AppStorage(DebugMfaEnabledOverride.userDefaultsKey) private var forceMfaEnabled = false
#if DEBUG
    @AppStorage(DebugBypassLockscreen.userDefaultsKey) private var bypassLockscreen = false
    @AppStorage(DebugPromotionPreset.userDefaultsKey) private var showAirPromotionPreset = false
#endif
    @State private var isLimitedOverride: Bool? = ConfigStore.shared.isLimitedOverride
    @State private var seasonalThemeOverride: ApiUpdate.UpdateConfig.SeasonalTheme? = ConfigStore.shared.seasonalThemeOverride

    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                
                Section {
                    Button("Share logs") {
                        log.info("Share logs requested")
                        Task { await onLogExport() }
                    }
                } header: {
                    Text("Logs")
                }
                
                Section {
                    Button("Add Testnet account") {
                        dismiss()
                        AppActions.showAddWallet(network: .testnet)
                    }
                } header: {
                    Text("Testnet")
                }

                Section {
                    Button("Clear activities cache") {
                        log.info("Clear activities cache")
                        Task {
                            await ActivityStore.debugOnly_clean()
                            do {
                                if let accountId = AccountStore.accountId {
                                    _ = try await AccountStore.activateAccount(accountId: accountId)
                                }
                            } catch {
                                log.error("\(error, .public)")
                            }
                            dismiss()
                        }
                    }
                }

                Section {
                    NavigationLink {
                        AirDebugPermissionsView()
                    } label: {
                        Text(lang("Permissions"))
                    }
                } footer: {
                    Text(lang("Token approvals and wallet permissions"))
                }
                
                // MARK: - TestFlight or debug
                
                if IS_DEBUG_OR_TESTFLIGHT_DEFAULT {

                    Text("TestFlight Only")
                        .header(.purple)

                    Section {
                        Toggle("View as production", isOn: $forceProductionMode)
                    } footer: {
                        Text("Makes `IS_DEBUG_OR_TESTFLIGHT` return false. Restart the app to apply it to startup-only behavior.")
                    }

                    Section {
                        Button(lang("$agent_consent_debug_reset_button")) {
                            log.info("Reset Agent consent state")
                            AirDebugActions.resetAgentConsentState()
                            dismiss()
                        }
                    } footer: {
                        Text(lang("$agent_consent_debug_reset_footer"))
                    }

                    Section {
                        Button("Force Intro") {
                            log.info("Force Intro")
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                AirDebugActions.forceIntro()
                            }
                        }
                    } footer: {
                        Text("Launches the intro flow for testing with existing accounts.")
                    }

                    Section {
                        Toggle("Force enable MFA", isOn: $forceMfaEnabled)

                        Picker("Is Limited Override", selection: $isLimitedOverride) {
                            Text("Disabled")
                                .tag(Optional<Bool>.none)
                            Text("True")
                                .tag(Optional(true))
                            Text("False")
                                .tag(Optional(false))
                        }
                        .pickerStyle(.navigationLink)

                        Picker("Seasonal Theme Override", selection: $seasonalThemeOverride) {
                            Text("Disabled")
                                .tag(Optional<ApiUpdate.UpdateConfig.SeasonalTheme>.none)
                            ForEach(ApiUpdate.UpdateConfig.SeasonalTheme.allCases, id: \.self) { seasonalTheme in
                                Text(seasonalTheme.rawValue)
                                    .tag(Optional(seasonalTheme))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text("Config")
                    }
                    .onAppear {
                        isLimitedOverride = ConfigStore.shared.isLimitedOverride
                        seasonalThemeOverride = ConfigStore.shared.seasonalThemeOverride
                    }
                    .onChange(of: isLimitedOverride) { isLimitedOverride in
                        ConfigStore.shared.isLimitedOverride = isLimitedOverride
                    }
                    .onChange(of: seasonalThemeOverride) { seasonalThemeOverride in
                        ConfigStore.shared.seasonalThemeOverride = seasonalThemeOverride
                    }
                    .onChange(of: forceMfaEnabled) { _ in
                        Task { @MainActor in
                            AccountConfigStore.liveValue.refreshDebugOverrides()
                        }
                    }
                }
                
                Section {
                    Button("Download database") {
                        do {
                            log.info("Download database requested")
                            let exportUrl = URL.temporaryDirectory.appending(component: "db-export-\(Int(Date().timeIntervalSince1970)).sqlite")
                            try db.orThrow("database not ready").backup(to: DatabaseQueue(path: exportUrl.path(percentEncoded: false)))
                            DispatchQueue.main.async {
                                let vc = UIActivityViewController(activityItems: [exportUrl], applicationActivities: nil)
                                topViewController()?.presentActivityViewController(vc)
                            }
                        } catch {
                            log.info("export failed: \(error, .public)")
                        }
                    }
                } footer: {
                    Text("Database file contains account addresses, settings, transaction history and other cached data but does not contain secrets such as the secret phrase or password.")
                }
                
                // MARK: - Debug only

#if DEBUG
                Text("Debug Only")
                    .header(.red)

                Section {
                    Toggle("Display log overlay", isOn: $displayLogOverlayEnabled)
                }
                .onChange(of: displayLogOverlayEnabled) { isEnabled in
                    setDisplayLogOverlayEnabled(isEnabled)
                }

                Section {
                    Toggle("Bypass lockscreen", isOn: $bypassLockscreen)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Debug builds only. Persists via `\(DebugBypassLockscreen.userDefaultsKey)`.")
                        Text("You can also enable it at launch with `\(DebugBypassLockscreen.environmentVariable)=1`.")
                        if DebugBypassLockscreen.isEnabledFromEnvironment {
                            Text("The current launch environment is already bypassing the lockscreen.")
                        }
                    }
                }

                Section {
                    Toggle("Show Air promotion preset", isOn: $showAirPromotionPreset)
                } footer: {
                    Text("Overrides the current account promotion config with the built-in 2026 Air campaign sample.")
                }
                .onChange(of: showAirPromotionPreset) { _ in
                    Task { @MainActor in
                        AccountConfigStore.liveValue.refreshDebugOverrides()
                    }
                }

                Section {
                    Button("Reactivate current account") {
                        Task {
                            log.info("Reactivate current account")
                            try! await AccountStore.reactivateCurrentAccount()
                        }
                    }
                }

                #if targetEnvironment(simulator)
                WalletsExportSection()
                #endif

                Section {
                    NavigationLink("Accounts in DB & Keychain") {
                        DebugAccountsView()
                    }
                } footer: {
                    Text("Shows sanitized account records from the native database and SDK keychain storage.")
                }

                Section {
                    Button("Delete credentials & exit", role: .destructive) {
                        WalletContext.KeychainWrapper.wipeKeychain()
                        exit(0)
                    }
                    
                    Button("Delete globalStorage & exit", role: .destructive) {
                        Task {
                            do {
                                try await GlobalStorage().deleteAll()
                                exit(0)
                            } catch {
                                log.error("\(error, .public)")
                            }
                        }
                    }
                }
#endif                
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 16)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("Debug menu"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("", systemImage: "xmark", action: { dismiss() }))
        }
    }
    
    func onLogExport() async {
        do {
            let logs = try await SupportDiagnostics.prepareLogsExportFile()
            await MainActor.run {
                let vc = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
                topViewController()?.presentActivityViewController(vc)
            }
        } catch {
            Log.shared.fault("failed to share logs \(error, .public)")
        }
    }
}

private extension View {
    func header(_ color: Color) -> some View {
        self
            .foregroundStyle(color)
            .font(.title2.weight(.bold))
            .listRowBackground(Color.clear)
            .offset(y: 8)
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct WalletsExportSection: View {
    @State private var isExporting = false
    @State private var successPath: String?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button {
                Task { await startExport() }
            } label: {
                if isExporting {
                    HStack {
                        Text("Export wallets")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Text("Export wallets")
                }
            }
            .disabled(isExporting)
        } footer: {
            Text("The dump can be imported at app launch via `\(AppWalletsExport.environmentVariable)`.")
        }
        .alert("Export complete", isPresented: Binding(
            get: { successPath != nil },
            set: { if !$0 { successPath = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let successPath {
                Text("The dump has been saved to \(successPath).")
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    @MainActor
    private func startExport() async {
        isExporting = true
        errorMessage = nil
        successPath = nil
        defer { isExporting = false }

        switch await AirDebugActions.exportWallets() {
        case .cancelled:
            return
        case .success(let result):
            successPath = result.fileURL.path
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
#endif

#if DEBUG
private struct DebugAccountsView: View {
    @State private var snapshot: DebugAccountsSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading, snapshot == nil {
                Section {
                    ProgressView("Loading accounts")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } header: {
                    Text("Error")
                }
            }

            if let snapshot {
                Section {
                    DebugKeyValueRow(title: "Current account", value: snapshot.currentAccountId ?? "<nil>")
                    DebugKeyValueRow(title: "DB accounts", value: "\(snapshot.dbAccountIds.count)")
                    DebugKeyValueRow(title: "Keychain accounts", value: "\(snapshot.keychainAccountIds.count)")
                    DebugKeyValueRow(title: "Missing in DB", value: "\(snapshot.missingInDbCount)")
                    DebugKeyValueRow(title: "Missing in keychain", value: "\(snapshot.missingInKeychainCount)")
                } header: {
                    Text("Summary")
                }

                if !snapshot.orderedAccountIds.isEmpty {
                    Section {
                        DebugMonospaceText(snapshot.orderedAccountIds.joined(separator: "\n"))
                    } header: {
                        Text("Native Order")
                    }
                }

                Section {
                    ForEach(snapshot.rows) { row in
                        NavigationLink {
                            DebugAccountDetailsView(row: row)
                        } label: {
                            DebugAccountRowView(row: row)
                        }
                    }
                } header: {
                    Text("Accounts")
                }
            }
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let snapshot {
                    Button {
                        AppActions.copyString(snapshot.exportText, toastMessage: "Account snapshot copied")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                Button {
                    Task {
                        await refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task {
            if snapshot == nil {
                await refresh()
            }
        }
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            snapshot = try await DebugAccountsSnapshot.load()
        } catch {
            errorMessage = String(reflecting: error)
        }
        isLoading = false
    }
}

private struct DebugAccountDetailsView: View {
    let row: DebugAccountDiagnosticRow

    var body: some View {
        List {
            Section {
                DebugKeyValueRow(title: "Status", value: row.statusTitle)
                DebugKeyValueRow(title: "In DB", value: row.existsInDb ? "yes" : "no")
                DebugKeyValueRow(title: "In keychain", value: row.existsInKeychain ? "yes" : "no")
            } header: {
                Text(row.accountId)
            }

            Section {
                if row.dbSummary.isEmpty {
                    Text("Missing")
                        .foregroundStyle(.secondary)
                } else {
                    DebugMonospaceText(row.dbSummary.joined(separator: "\n"))
                }
            } header: {
                Text("DB Summary")
            }

            Section {
                if let dbJson = row.dbJson {
                    DebugMonospaceText(dbJson)
                } else {
                    Text("Missing")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("DB JSON")
            }

            Section {
                if row.keychainSummary.isEmpty {
                    Text("Missing")
                        .foregroundStyle(.secondary)
                } else {
                    DebugMonospaceText(row.keychainSummary.joined(separator: "\n"))
                }
            } header: {
                Text("Keychain Summary")
            }

            Section {
                if let keychainJson = row.keychainJson {
                    DebugMonospaceText(keychainJson)
                } else {
                    Text("Missing")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Keychain JSON")
            } footer: {
                Text("Sensitive fields are redacted.")
            }
        }
        .navigationTitle(row.accountId)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    AppActions.copyString(row.exportText, toastMessage: "Account copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }
}

private struct DebugAccountRowView: View {
    let row: DebugAccountDiagnosticRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.accountId)
                    .font(.headline.monospaced())
                Spacer(minLength: 8)
                Text(row.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            if !row.dbSummary.isEmpty {
                Text("DB: \(row.dbSummary.joined(separator: " | "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !row.keychainSummary.isEmpty {
                Text("Keychain: \(row.keychainSummary.joined(separator: " | "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        if row.existsInDb, row.existsInKeychain {
            return .green
        }
        if row.existsInKeychain {
            return .orange
        }
        return .red
    }
}

private struct DebugKeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct DebugMonospaceText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DebugAccountsSnapshot: Equatable {
    let generatedAt: Date
    let currentAccountId: String?
    let orderedAccountIds: [String]
    let dbAccountIds: [String]
    let keychainAccountIds: [String]
    let rows: [DebugAccountDiagnosticRow]

    var missingInDbCount: Int {
        rows.filter { !$0.existsInDb && $0.existsInKeychain }.count
    }

    var missingInKeychainCount: Int {
        rows.filter { $0.existsInDb && !$0.existsInKeychain }.count
    }

    var exportText: String {
        var parts: [String] = [
            "generatedAt=\(generatedAt.formatted(.iso8601))",
            "currentAccountId=\(currentAccountId ?? "<nil>")",
            "orderedAccountIds=\(orderedAccountIds.joined(separator: ","))",
            "dbAccountIds=\(dbAccountIds.joined(separator: ","))",
            "keychainAccountIds=\(keychainAccountIds.joined(separator: ","))",
            "missingInDb=\(missingInDbCount)",
            "missingInKeychain=\(missingInKeychainCount)",
        ]
        parts.append(contentsOf: rows.map(\.exportText))
        return parts.joined(separator: "\n\n")
    }

    @MainActor
    static func load() async throws -> DebugAccountsSnapshot {
        let database = try db.orThrow("database not ready")
        let dbAccounts = try await database.read { db in
            try MAccount.fetchAll(db)
        }
        let keychainRead = DebugKeychainAccounts.read()
        let dbById = Dictionary(uniqueKeysWithValues: dbAccounts.map { ($0.id, $0) })
        let allAccountIds = DebugAccountSort.sortedAccountIds(Array(Set(dbById.keys).union(keychainRead.accounts.keys)))

        let rows = allAccountIds.map { accountId in
            DebugAccountDiagnosticRow(
                accountId: accountId,
                dbAccount: dbById[accountId],
                keychainAccount: keychainRead.accounts[accountId],
                keychainParseError: keychainRead.parseError
            )
        }

        return DebugAccountsSnapshot(
            generatedAt: Date(),
            currentAccountId: AccountStore.accountId,
            orderedAccountIds: Array(AccountStore.orderedAccountIds),
            dbAccountIds: DebugAccountSort.sortedAccountIds(Array(dbById.keys)),
            keychainAccountIds: DebugAccountSort.sortedAccountIds(Array(keychainRead.accounts.keys)),
            rows: rows
        )
    }
}

private struct DebugAccountDiagnosticRow: Identifiable, Equatable {
    let accountId: String
    let existsInDb: Bool
    let existsInKeychain: Bool
    let dbSummary: [String]
    let keychainSummary: [String]
    let dbJson: String?
    let keychainJson: String?

    var id: String { accountId }

    var statusTitle: String {
        switch (existsInDb, existsInKeychain) {
        case (true, true):
            return "DB + Keychain"
        case (true, false):
            return "DB only"
        case (false, true):
            return "Keychain only"
        case (false, false):
            return "Missing"
        }
    }

    var exportText: String {
        """
        accountId=\(accountId)
        status=\(statusTitle)
        dbSummary=\(dbSummary.joined(separator: " | "))
        keychainSummary=\(keychainSummary.joined(separator: " | "))
        dbJson=\(dbJson ?? "<missing>")
        keychainJson=\(keychainJson ?? "<missing>")
        """
    }

    init(
        accountId: String,
        dbAccount: MAccount?,
        keychainAccount: [String: Any]?,
        keychainParseError: String?
    ) {
        self.accountId = accountId
        self.existsInDb = dbAccount != nil
        self.existsInKeychain = keychainAccount != nil
        self.dbSummary = dbAccount.map(Self.makeDbSummary(account:)) ?? []
        self.keychainSummary = keychainAccount.map(Self.makeKeychainSummary(account:)) ?? {
            if let keychainParseError {
                return ["parseError=\(keychainParseError)"]
            }
            return []
        }()
        self.dbJson = dbAccount?.jsonStringPretty()
        self.keychainJson = keychainAccount.map { DebugJSON.prettyString(DebugJSON.sanitized($0)) }
    }

    private static func makeDbSummary(account: MAccount) -> [String] {
        var result = [
            "title=\(account.title ?? "<nil>")",
            "type=\(account.type.rawValue)",
            "temporary=\(account.isTemporary == true ? "true" : "false")",
        ]
        result.append(contentsOf: account.byChain.keys.sorted().compactMap { chain in
            guard let value = account.byChain[chain] else { return nil }
            return DebugAccountFields.chainSummary(chain: chain, value: value)
        })
        return result
    }

    private static func makeKeychainSummary(account: [String: Any]) -> [String] {
        var result: [String] = []
        if let type = account["type"] as? String {
            result.append("type=\(type)")
        }
        if let mnemonicEncrypted = account["mnemonicEncrypted"] as? String {
            result.append("mnemonicEncrypted=<redacted length=\(mnemonicEncrypted.count)>")
        }
        if let driver = account["driver"] as? String {
            result.append("driver=\(driver)")
        }
        if let deviceName = account["deviceName"] as? String {
            result.append("deviceName=\(deviceName)")
        }
        result.append(contentsOf: DebugAccountFields.keychainChainSummaries(account: account))
        return result
    }
}

private enum DebugKeychainAccounts {
    static func read() -> (accounts: [String: [String: Any]], parseError: String?) {
        let raw = KeychainStorageProvider.get(key: "accounts")
        guard let value = raw.1 else {
            return ([:], raw.0 ? "accounts key exists but value is nil" : nil)
        }
        do {
            guard let object = try JSONSerialization.jsonObject(withString: value) as? [String: Any] else {
                return ([:], "accounts is not a dictionary")
            }
            let accounts = object.reduce(into: [String: [String: Any]]()) { result, item in
                if let account = item.value as? [String: Any] {
                    result[item.key] = account
                }
            }
            return (accounts, nil)
        } catch {
            return ([:], String(reflecting: error))
        }
    }
}

private enum DebugAccountFields {
    static func chainSummary(chain: String, value: AccountChain) -> String {
        var parts = ["\(chain)=\(short(value.address))"]
        if let domain = value.domain {
            parts.append("domain=\(domain)")
        }
        if value.isMultisig == true {
            parts.append("multisig")
        }
        if let derivation = value.derivation {
            parts.append("derivation=\(derivation.path)#\(derivation.index)")
        }
        if value.mfa != nil {
            parts.append("mfa")
        }
        return parts.joined(separator: " ")
    }

    static func keychainChainSummaries(account: [String: Any]) -> [String] {
        chainDictionaries(account: account).map { chain, value in
            var parts = ["\(chain)=\(short(value["address"] as? String))"]
            if let domain = value["domain"] as? String {
                parts.append("domain=\(domain)")
            }
            if let version = value["version"] as? String {
                parts.append("version=\(version)")
            }
            if bool(value["isMultisig"]) == true {
                parts.append("multisig")
            }
            if let derivation = value["derivation"] as? [String: Any] {
                let path = derivation["path"] as? String ?? "?"
                let index = derivation["index"].map { "\($0)" } ?? "?"
                parts.append("derivation=\(path)#\(index)")
            }
            if value["mfa"] != nil {
                parts.append("mfa")
            }
            return parts.joined(separator: " ")
        }
    }

    private static func chainDictionaries(account: [String: Any]) -> [(String, [String: Any])] {
        if let byChain = account["byChain"] as? [String: Any] {
            return byChain.keys.sorted().compactMap { chain in
                guard let value = byChain[chain] as? [String: Any] else { return nil }
                return (chain, value)
            }
        }

        return ["ton", "tron", "solana", "ethereum", "base", "bnb", "polygon", "arbitrum"]
            .compactMap { chain in
                guard let value = account[chain] as? [String: Any] else { return nil }
                return (chain, value)
            }
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    private static func short(_ value: String?) -> String {
        guard let value, value.count > 18 else {
            return value ?? "<nil>"
        }
        return "\(value.prefix(8))...\(value.suffix(6))"
    }
}

private enum DebugJSON {
    private static let sensitiveKeys: Set<String> = [
        "mnemonicEncrypted",
        "privateKeyEncrypted",
        "authToken",
        "words",
    ]

    static func sanitized(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { result, item in
                if sensitiveKeys.contains(item.key) {
                    result[item.key] = redacted(item.value)
                } else {
                    result[item.key] = sanitized(item.value)
                }
            }
        }
        if let array = value as? [Any] {
            return array.map(sanitized)
        }
        return value
    }

    static func prettyString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return String(describing: value)
        }
        return string
    }

    private static func redacted(_ value: Any) -> String {
        if let string = value as? String {
            return "<redacted length=\(string.count)>"
        }
        return "<redacted>"
    }
}

private enum DebugAccountSort {
    static func sortedAccountIds(_ ids: [String]) -> [String] {
        ids.sorted { lhs, rhs in
            let left = components(lhs)
            let right = components(rhs)

            if left.hasNumber != right.hasNumber {
                return left.hasNumber
            }
            if left.number != right.number {
                return left.number < right.number
            }
            if left.networkRank != right.networkRank {
                return left.networkRank < right.networkRank
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func components(_ accountId: String) -> (hasNumber: Bool, number: Int, networkRank: Int) {
        let firstPart = accountId.split(separator: "-").first.map(String.init)
        let number = firstPart.flatMap(Int.init)
        let networkRank: Int
        if accountId.contains("mainnet") {
            networkRank = 0
        } else if accountId.contains("testnet") {
            networkRank = 1
        } else {
            networkRank = 2
        }
        return (number != nil, number ?? Int.max, networkRank)
    }
}
#endif
