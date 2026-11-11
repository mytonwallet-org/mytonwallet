
import SwiftUI
import WalletContext
import WalletCore
import UIComponents

struct ImportExistingPickerView: View {

    let introModel: IntroModel
    var onHeightChange: (CGFloat) -> ()
    var shouldIgnoreHorizontalSafeArea = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            InsetSection(addDividers: false) {
                WalletPickerOptionRow(
                    icon: "KeyIcon30",
                    title: lang("$secret_words"),
                    subtitle: localizedIntegerDigits(in: lang("Restore wallet from 12 or 24 words")),
                    showsDivider: true,
                    accessibilityId: "add_wallet_secret_words",
                    onTap: onImport
                )
                WalletPickerOptionRow(
                    icon: "LedgerIcon30",
                    title: lang("Ledger"),
                    subtitle: lang("Connect your hardware wallet"),
                    accessibilityId: "add_wallet_ledger",
                    onTap: onLedger
                )
            }

            InsetSection(addDividers: false) {
                WalletPickerOptionRow(
                    icon: "ViewIcon30",
                    title: lang("View Any Address"),
                    subtitle: lang("Watch wallet in read-only mode"),
                    accessibilityId: "add_wallet_view",
                    onTap: onView
                )
            }
            .padding(.top, 24)
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
        .fixedSize(horizontal: false, vertical: true)
        .ignoresSafeArea(.container, edges: shouldIgnoreHorizontalSafeArea ? .horizontal : [])
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
            onHeightChange(height)
        }
    }

    func onImport() {
        introModel.onImportMnemonic()
    }

    func onLedger() {
        introModel.onLedger()
    }

    func onView() {
        introModel.onAddViewWallet()
    }
}
