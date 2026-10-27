import SwiftUI
import WalletContext
import WalletCore

struct WalletRecoveryDiagnosticsSection: View {
    let diagnostics: WalletRecoveryDiagnostics

    var body: some View {
        Section {
            NavigationLink {
                WalletRecoveryDiagnosticsView(diagnostics: diagnostics)
            } label: {
                LabeledContent("Wallet recovery diagnostics", value: "\(diagnostics.accounts.count)")
            }
        } footer: {
            Text("Some wallets need attention after the secure storage migration. Details are available for support.")
        }
    }
}

private struct WalletRecoveryDiagnosticsView: View {
    let diagnostics: WalletRecoveryDiagnostics

    var body: some View {
        List {
            Section {
                Text("These wallets were marked for recovery or have no secret in Enclave after migration. Contact support before removing them or reinstalling the app.")
                LabeledContent("Legacy migration allowed", value: diagnostics.isLegacyMigrationAllowed ? "Yes" : "No")
                LabeledContent("Checked") {
                    Text(diagnostics.generatedAt, format: .dateTime)
                }
            }

            ForEach(diagnostics.accounts) { account in
                Section {
                    LabeledContent("Account ID", value: account.id)
                        .textSelection(.enabled)
                    LabeledContent("Enclave secret", value: title(for: account.enclaveSecret))
                    ForEach(account.legacySources, id: \.key) { source in
                        LabeledContent(source.key, value: title(for: source.ciphertext))
                    }
                } header: {
                    Text(AccountStore.accountsById[account.id]?.displayName ?? account.id)
                }
            }

            Section {
                Button("Copy diagnostics") {
                    AppActions.copyString(diagnostics.exportText, toastMessage: "Diagnostics copied")
                }
            } footer: {
                Text("Only storage presence is checked. Present encrypted data may still be unreadable. No secret phrases, passwords or encrypted contents are included. Share logs from the debug menu to include these details with the app logs.")
            }
        }
        .navigationTitle("Wallet recovery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func title(for presence: WalletRecoveryDiagnostics.Presence) -> String {
        switch presence {
        case .present: "Present"
        case .missing: "Not found"
        case .unavailable: "Could not check"
        }
    }
}
