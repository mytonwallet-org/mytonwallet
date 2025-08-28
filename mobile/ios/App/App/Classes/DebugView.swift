
import AirAsFramework
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import SwiftKeychainWrapper
import GRDB

private let log = Log("DebugView")


@MainActor func _showDebugView() {
    let vc = UIHostingController(rootView: DebugView())
    topViewController()?.present(vc, animated: true)
}


struct DebugView: View {
    
    @State private var showDeleteAllAlert: Bool = false
    @AppStorage("debug_languageSwitcher") private var languageSwitcher = false
    
    var body: some View {
        NavigationStack {
            List {
                
#if DEBUG
                Section {
                    Button("Switch to Air") {
                        log.info("Switching to Air")
                        UIApplication.shared.connectedSceneDelegate?.switchToAir()
                    }
                    Button("Switch to Air (force reload)") {
                        log.info("Switching to Air (force reload)")
                        AirLauncher.isOnTheAir = true
                        UIApplication.shared.connectedSceneDelegate?.appSwitcher?.startTheApp()
                    }
                    Button("Switch to Capacitor") {
                        log.info("Switching to Capacitor")
                        AirLauncher.isOnTheAir = false
                        UIApplication.shared.connectedSceneDelegate?.appSwitcher?.startTheApp()
                    }
                }
                
                Section {
                    Button("Reactivate current account") {
                        Task {
                            log.info("Reactivate current account")
//                            try! await AccountStore.reactivateCurrentAccount()
                        }
                    }
                }
#endif
                
                Section {
                    Button("Share logs") {
                        log.info("Share logs requested")
                        logKeychainState()
                        Task {
                            do {
                                let logs = try await LogStore.shared.exportFile()
                                DispatchQueue.main.async {
                                    let vc = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
                                    topViewController()?.present(vc, animated: true)
                                }
                            } catch {
                                Log.shared.fault("failed to share logs \(error, .public)")
                            }
                        }
                    }
                }
                
                Section {
                    Toggle("Language Switcher", isOn: $languageSwitcher)
                } header: {
                    Text("Experimental Features")
                } footer: {
                    Text("These features are not finished. Enable at your own risk.")
                }
                
                
#if DEBUG
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
//                    Button("Delete credentials & exit", role: .destructive) {
//                        WalletContext.KeychainWrapper.wipeKeychain()
//                        exit(0)
//                    }
                    
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
                
//                Section {
//                    EmptyView()
//                } footer: {
//                    let accs = KeychainStorageProvider.get(key: "accounts")
//                    let credentials = CapacitorCredentialsStorage.getCredentials()
//                    let areCredentialsValid = credentials?.password.wholeMatch(of: /[0-9]{4}/) != nil || credentials?.password.wholeMatch(of: /[0-9]{6}/) != nil
//                    
//                    Text("""
//                    keys=\(KeychainStorageProvider.keys())
//                    stateVersion=\(KeychainStorageProvider.get(key: "stateVersion"))
//                    currentAccountId=\(KeychainStorageProvider.get(key: "currentAccountId"))
//                    clientId=\(KeychainStorageProvider.get(key: "clientId"))
//                    baseCurrency=\(KeychainStorageProvider.get(key: "baseCurrency"))
//                    accounts=\(accs.0) len=\(accs.1?.count ?? -1)
//                    credentials discovered=\(credentials != nil) valid=\(areCredentialsValid)
//                    """)
//                    .font(.footnote.monospaced())
//                    .foregroundStyle(.secondary)
//                }
#endif                
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 16)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("Debug menu"))
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    func logKeychainState() {
        log.info("\(KeychainStorageProvider as Any, .public)")
        log.info("\(KeychainStorageProvider.keys() as Any, .public)")
        log.info("stateVersion = \(KeychainStorageProvider.get(key: "stateVersion") as Any, .public)")
        log.info("currentAccountId = \(KeychainStorageProvider.get(key: "currentAccountId") as Any, .public)")
        log.info("clientId = \(KeychainStorageProvider.get(key: "clientId") as Any, .public)")
        log.info("baseCurrency = \(KeychainStorageProvider.get(key: "baseCurrency") as Any, .public)")
        let accs = KeychainStorageProvider.get(key: "accounts")
        log.info("accounts = \(accs.0 as Any) \(accs.1?.count as Any)")
        
        let areCredentialsValid: Bool
        if let credentials = CapacitorCredentialsStorage.getCredentials() {
            log.info("credentials discovered username=\(credentials.username, .public) password=\(credentials.password, .redacted) password.count=\(credentials.password.count)")
            areCredentialsValid = credentials.password.wholeMatch(of: /[0-9]{4}/) != nil || credentials.password.wholeMatch(of: /[0-9]{6}/) != nil
        } else {
            log.error("credentials do not exist")
            areCredentialsValid = false
        }
        if areCredentialsValid == false {
            log.error("credentials are invalid")
        }
    }
}
