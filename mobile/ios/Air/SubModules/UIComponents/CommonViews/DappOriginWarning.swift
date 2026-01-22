
import Foundation
import SwiftUI
import WalletContext

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
                topWViewController()?.showTip(title: lang("Unverified Source"), kind: .warning) {
                    EmptyView()
                }
            }
            .padding(-10)
    }
}
