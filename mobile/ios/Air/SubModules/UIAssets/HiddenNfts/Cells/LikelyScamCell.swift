
import SwiftUI
import Perception
import UIComponents
import WalletCore
import WalletContext

struct LikelyScamCell: View {

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
                Toggle("", isOn: Binding(
                    get: { state.isUnhiddenByUser },
                    set: { newValue in
                        state.isUnhiddenByUser = newValue
                        action(newValue)
                    }
                ))
                .labelsHidden()
                .padding(.trailing, 12)
            }
        }
    }
}
