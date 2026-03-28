//
//  BaseCurrencyValueText.swift
//  MyTonWalletAir
//
//  Created by nikstar on 22.11.2024.
//

import SwiftUI
import WalletCore
import WalletContext


public struct FeeView: View {
    
    private let token: ApiToken
    private let nativeToken: ApiToken
    private let fee: MFee?
    private let explainedTransferFee: ExplainedTransferFee?
    private let includeLabel: Bool
    
    private var shouldShowDetails: Bool { explainedTransferFee?.supportsLegacyDetailsView == true }
    
    public init(token: ApiToken, nativeToken: ApiToken, fee: MFee?, explainedTransferFee: ExplainedTransferFee?, includeLabel: Bool) {
        self.token = token
        self.nativeToken = nativeToken
        self.fee = fee
        self.explainedTransferFee = explainedTransferFee
        self.includeLabel = includeLabel
    }
    
    public var body: some View {
        if let fee = fee ?? explainedTransferFee?.realFee {
            if shouldShowDetails {
                Button(action: showFeeDetails) {
                    feeContent(fee, showsDetailsIcon: true)
                }
                .padding(-2)
                .buttonStyle(.plain)
                .animation(.snappy, value: shouldShowDetails)
            } else {
                feeContent(fee, showsDetailsIcon: false)
            }
        }
    }
    
    @ViewBuilder
    private func feeContent(_ fee: MFee, showsDetailsIcon: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            let value = Text(fee.toString(token: token, nativeToken: nativeToken))
            if includeLabel {
                let label = Text(lang("$fee_value_with_colon", arg1: ""))
                Text("\(label)\(value)")
            } else {
                value
            }
            if showsDetailsIcon {
                Image(systemName: "questionmark.circle.fill")
                    .imageScale(.medium)
                    .foregroundStyle(Color(.air.secondaryLabel.withAlphaComponent(0.3)))
            }
        }
        .padding(2)
        .contentShape(.rect)
    }

    func showFeeDetails() {
        if shouldShowDetails, let explainedTransferFee {
            if let vc = topWViewController() {
                vc.view.endEditing(true)
                vc.showTip(title: "Blockchain Fee Details", wide: true) {
                    FeeDetailsView(nativeToken: nativeToken, fee: explainedTransferFee)
                }
            }
        }
    }
}  
