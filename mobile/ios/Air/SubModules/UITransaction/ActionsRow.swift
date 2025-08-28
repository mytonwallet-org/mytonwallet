
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Kingfisher
import UIPasscode

struct ActionsRow: View {
    
    var activity: ApiActivity
    var onDetailsExpanded: () -> ()
    
    var shouldShowRepeat: Bool {
        guard let account  = AccountStore.account, account.type != .view else { return false }
        
        if activity.swap != nil {
            return account.supportsSwap
        }
        
        guard let transaction = activity.transaction else { return false }
        
        return transaction.isStaking || (!transaction.isIncoming && transaction.nft == nil)
    }
    
    var body: some View {
        HStack {
            ActionButton("Details", "ActivityDetails22") {
                onDetailsExpanded()
            }
            if shouldShowRepeat {
                ActionButton("Repeat", "ActivityRepeat22") {
                    AppActions.repeatActivity(activity)
                }
            }
            if !activity.isBackendSwapId {
                ActionButton("Share", "ActivityShare22") {
                    let chain = ApiChain(rawValue: TokenStore.tokens[activity.slug]?.chain ?? "")
                    if let chain {
                        let txHash = activity.parsedTxId.hash
                        let url = ExplorerHelper.txUrl(chain: chain, txHash: txHash)
                        AppActions.shareUrl(url)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

struct ActionButton: View {

    var title: String
    var icon: String
    var action: () -> ()

    init(_ title: String, _ icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image.airBundle(icon)
                    .padding(2)
                Text(lang(title).lowercased())
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(ActionButtonStyle())
    }
}

struct ActionButtonStyle: ButtonStyle {

    @State private var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .opacity(isHighlighted ? 0.5 : 1)
            .foregroundStyle(Color(WTheme.tint))
            .background(Color(WTheme.groupedItem), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                withAnimation(.spring(duration: 0.1)) {
                    isHighlighted = true
                }
            }.onEnded { _ in
                withAnimation(.spring(duration: 0.5)) {
                    isHighlighted = false
                }
            })
    }
}
