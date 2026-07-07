
import SwiftUI
import Perception
import UIComponents
import WalletCore
import WalletContext

struct HiddenByUserCell: View {

    let state: HiddenNftCellViewModel
    var onPreviewTap: () -> Void
    var action: (Bool) -> ()

    var body: some View {
        WithPerceptionTracking {
            HStack {
                Button(action: onPreviewTap) {
                    NftPreviewRow(nft: state.displayNft.nft, horizontalPadding: 12, verticalPadding: 10)
                }
                .buttonStyle(InsetButtonStyle())
                .padding(.trailing, -2)

                Button(action: toggle) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: state.isHiddenByUser ? "eye.fill" : "eye.slash.fill")
                            .imageScale(.small)
                        Text(lang(state.isHiddenByUser ? "Unhide" : "Hide"))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(.capsule)
                }
                .buttonBorderShape(.capsule)
                .buttonStyle(.bordered)
                .tint(Color.accentColor.opacity(state.isHiddenByUser ? 0 : 1))
                .overlay { Capsule().strokeBorder(Color.accentColor.opacity(state.isHiddenByUser ? 0.5 : 0), lineWidth: 0.5) }
                .animation(.smooth(duration: 0.15), value: state.isHiddenByUser)
                .padding(.trailing, 12)
            }
        }
    }

    func toggle() {
        let newValue = !state.isHiddenByUser
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.isHiddenByUser = newValue
        }
        action(newValue)
    }
}
