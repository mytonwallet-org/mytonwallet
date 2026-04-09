
import Foundation
import SwiftUI
import WalletContext

@MainActor public func showDappOriginWarningTip() {
    topWViewController()?.showTip(title: lang("Unverified Source"), kind: .warning) {
        Text(langMd("$reopen_in_iab_explore", arg1: lang("Explore")))
            .multilineTextAlignment(.center)
    }
}

public struct DappOriginWarning: View {
    
    public init() {}
    
    public var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.orange)
            .imageScale(.small)
            .fontWeight(.bold)
            .padding(10)
            .contentShape(.rect)
            .onTapGesture {
                showDappOriginWarningTip()
            }
            .padding(-10)
    }
}
