
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

struct LikelyScamCell: View {

    var displayNft: DisplayNft
    var isHighlighted: Bool
    var action: (Bool) -> ()
    
    @State private var isUnhiddenByUser = false
    
    var body: some View {
        HStack {
            NftPreviewRow(nft: displayNft.nft, horizontalPadding: 12, verticalPadding: 10)
                .padding(.trailing, -2)
            Toggle("", isOn: $isUnhiddenByUser)
                .labelsHidden()
                .padding(.trailing, 12)
        }
        .highlightBackground(isHighlighted)
        .onChange(of: isUnhiddenByUser) { newValue in
            action(newValue)
        }
        .onChange(of: displayNft) { nft in
            isUnhiddenByUser = displayNft.isUnhiddenByUser
        }
        .onAppear {
            isUnhiddenByUser = displayNft.isUnhiddenByUser
        }
    }
}
