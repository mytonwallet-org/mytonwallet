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

struct ImportExistingPickerView: View {
    
    let introModel: IntroModel
    var onHeightChange: (CGFloat) -> ()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            InsetSection(dividersInset: 50) {
                Item(icon: "KeyIcon30", text: lang("%counts% Secret Words", arg1: "12/24"), onTap: onImport)
                Item(icon: "LedgerIcon30", text: "Ledger", onTap: onLedger)
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
