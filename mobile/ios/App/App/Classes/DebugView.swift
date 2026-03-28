
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
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(trailing: Button("", systemImage: "xmark", action: { dismiss() }))
        }
    }
    
    func onLogExport() async {
        do {
            let logs = try await SupportDiagnostics.prepareLogsExportFile()
            await MainActor.run {
                let vc = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
                topViewController()?.present(vc, animated: true)
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
