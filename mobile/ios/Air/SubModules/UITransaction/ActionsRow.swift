
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
        
        switch activity {
        case .transaction(let tx):
            if tx.isStaking {
                return account.supportsEarn
            }
            if tx.isIncoming || tx.type != nil || tx.nft != nil {
                return false
            }
            return account.supportsSend
        case .swap(let apiSwapActivity):
            return account.supportsSwap
        }
    }
    
    var body: some View {
        HStack {
            ActionButton(lang("Details"), "ActivityDetails22") {
                onDetailsExpanded()
            }
            if shouldShowRepeat {
                ActionButton(lang("Repeat"), "ActivityRepeat22") {
                    AppActions.repeatActivity(activity)
                }
            }
            if !activity.isBackendSwapId {
                ActionButton(lang("Share"), "ActivityShare22") {
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
                Text(title.lowercased())
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(ActionButtonStyle())
    }
}

struct ActionButtonStyle: PrimitiveButtonStyle {

    @State private var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .opacity(isHighlighted ? 0.5 : 1)
            .foregroundStyle(Color(WTheme.tint))
            .background(Color(WTheme.groupedItem), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: S.actionButtonCornerRadius))
            .onTapGesture {
                configuration.trigger()
            }
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
