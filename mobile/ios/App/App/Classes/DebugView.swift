
import AirAsFramework
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import GRDB
#if canImport(Capacitor)
import SwiftKeychainWrapper
#endif

private let log = Log("DebugView")


@MainActor func _showDebugView() {
    let vc = UIHostingController(rootView: DebugView())
    topViewController()?.present(vc, animated: true)
}


struct DebugView: View {
    
    @State private var showDeleteAllAlert: Bool = false
    @AppStorage("debug_hideSegmentedControls") private var hideSegmentedControls = false
    @AppStorage("debug_glassOpacity") var glassOpacity: Double = 1
    @AppStorage("debug_gradientIsHidden") var gradientIsHidden: Bool = true
    @AppStorage("debug_displayLogOverlay") private var displayLogOverlayEnabled = false
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
                        AppActions.showAddWallet(network: .testnet, showCreateWallet: true, showSwitchToOtherVersion: false)
                    }
                } header: {
                    Text("Testnet")
                }
                
                Section {
                    Button("Switch to Air") {
                        log.info("Switch to Air")
                        UIApplication.shared.open(URL(string: "mtw://air")!)
                        dismiss()
                    }
                    Button("Switch to Classic") {
                        log.info("Switch to Classic")
                        UIApplication.shared.open(URL(string: "mtw://classic")!)
                    }
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
                
                // MARK: - TestFlight or debug
                
                if IS_DEBUG_OR_TESTFLIGHT {

                    Text("TestFlight Only")
                        .header(.purple)

                    Section {
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
                    Button("Reactivate current account") {
                        Task {
                            log.info("Reactivate current account")
                            try! await AccountStore.reactivateCurrentAccount()
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
                                topViewController()?.present(vc, animated: true)
                            }
                        } catch {
                            log.info("export failed: \(error, .public)")
                        }
                    }
                } footer: {
                    Text("Database file contains account addresses, settings, transaction history and other cached data but does not contain secrets such as the secret phrase or password.")
                }

                Section {
                    Button("Delete credentials & exit", role: .destructive) {
                        WalletContext.KeychainWrapper.wipeKeychain()
                        exit(0)
                    }
                    
                    Button("Delete globalStorage & exit", role: .destructive) {
                        Task {
                            do {
                                try await GlobalStorage.deleteAll()
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
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(trailing: Button("", systemImage: "xmark", action: { dismiss() }))
        }
    }
    
    func onLogExport() async {
        logKeychainState()
        logAccountState()
        LogStore.shared.syncronize()
        do {
            let logs = try await LogStore.shared.exportFile()
            await MainActor.run {
                let vc = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
                topViewController()?.present(vc, animated: true)
            }
        } catch {
            Log.shared.fault("failed to share logs \(error, .public)")
        }
    }
    
    func logKeychainState() {
        log.info("keychain state:")
        log.info("keys = \(KeychainStorageProvider.keys() as Any, .public)")
        log.info("stateVersion = \(KeychainStorageProvider.get(key: "stateVersion") as Any, .public)")
        log.info("currentAccountId = \(KeychainStorageProvider.get(key: "currentAccountId") as Any, .public)")
        log.info("clientId = \(KeychainStorageProvider.get(key: "clientId") as Any, .public)")
        log.info("baseCurrency = \(KeychainStorageProvider.get(key: "baseCurrency") as Any, .public)")
        let accs = KeychainStorageProvider.get(key: "accounts")
        var accountIdsInKeychain: [String]?
        if let value = accs.1, let keys = try? (JSONSerialization.jsonObject(withString: value) as? [String: Any])?.keys {
            accountIdsInKeychain = Array(keys)
        }
        log.info("accounts = \(accs.0 as Any) length=\(accs.1?.count ?? -1)")
        log.info("accountIds in keychain = \(accountIdsInKeychain?.jsonString() ?? "<accounts is not a valid dict>", .public)")
        
        let areCredentialsValid: Bool
        if let credentials = CapacitorCredentialsStorage.getCredentials() {
            log.info("credentials discovered username = \(credentials.username, .public) password.count = \(credentials.password.count)")
            areCredentialsValid = credentials.password.wholeMatch(of: /[0-9]{4}/) != nil || credentials.password.wholeMatch(of: /[0-9]{6}/) != nil
        } else {
            log.info("credentials do not exist")
            areCredentialsValid = false
        }
        log.info("areCredentialsValid = \(areCredentialsValid)")
    }
    
    func logAccountState() {
        log.info("account state:")
        log.info("currentAccountId = \(AccountStore.accountId ?? "<AccountStore.accountId is nil>", .public)")
        let orderedAccountIds = AccountStore.orderedAccountIds
        log.info("orderedAccountIds = #\(orderedAccountIds.count) \(orderedAccountIds.jsonString(), .public)")
        let accountsById = AccountStore.accountsById
        log.info("accountsById = #\(accountsById.count) \(accountsById.jsonString(), .public)")
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
