//
//  AccountTypePickerView.swift
//  AirAsFramework
//
//  Created by nikstar on 25.08.2025.
//

import SwiftUI
import WalletContext
import WalletCore
import UIComponents
import UIPasscode

struct ImportExistingPickerView: View {
    
    let introModel: IntroModel
    var onHeightChange: (CGFloat) -> ()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
//            Text(lang("$import_hint"))
//                .padding(.horizontal, 32)
//                .padding(.bottom, 8)
//                .multilineTextAlignment(.center)

            InsetSection(dividersInset: 50) {
                Item(icon: "KeyIcon30", text: lang("12/24 Secret Words"), onTap: onImport)
//                Item(icon: "QrIcon30", text: lang("Other Device"), onTap: onScan)
                Item(icon: "LedgerIcon30", text: lang("Ledger"), onTap: onLedger)
            }

            InsetSection(dividersInset: 50) {
                Item(icon: "ViewIcon30", text: lang("View Any Address"), additionalPadding: true, onTap: onView)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 32)
        .fixedSize(horizontal: false, vertical: true)
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
    
    func onWalletVersion() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppActions.showImportWalletVersion()
        }
    }
}


private struct Item: View {
    
    var icon: String
    var text: String
    var additionalPadding: Bool = false
    var onTap: () -> ()
    
    var body: some View {
        InsetButtonCell(verticalPadding: additionalPadding ? 9 : 7, action: onTap) {
            HStack(spacing: 16) {
                Image.airBundle(icon)
                    .clipShape(.rect(cornerRadius: 8))
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image.airBundle("RightArrowIcon")
            }
            .foregroundStyle(Color(WTheme.primaryLabel))
            .backportGeometryGroup()
        }
    }
}

private struct Divider: View {
    var body: some View {
        Capsule()
            .frame(width: 64, height: 0.667)
            .offset(y: 1.333)
    }
}
