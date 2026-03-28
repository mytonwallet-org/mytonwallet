
import SwiftUI
import WalletContext
import WalletCore
import Perception

public struct NftOverviewView: View {
    
    var nfts: [ApiNft]
    var isOutgoing: Bool
    var text: String?
    var addressViewModel: AddressViewModel
    
    public init(nfts: [ApiNft], isOutgoing: Bool, text: String? = nil, addressViewModel: AddressViewModel) {
        self.nfts = nfts
        self.isOutgoing = isOutgoing
        self.text = text
        self.addressViewModel = addressViewModel
    }
    
    public var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                if nfts.count == 1 {
                    NftImage(nft: nfts[0], animateIfPossible: false)
                        .frame(width: 144, height: 144)
                        .clipShape(.rect(cornerRadius: 12))
                        .padding(.bottom, 16)
                        .padding(.top, -12)
                } else {
                    NftPreviewFlowRepresentable(nfts: nfts, maxItems: 30, maxRows: 3, horAlignment: .left)
                        .frame(width: 200)
                        .frame(maxHeight: NftPreviewFlowRepresentable.heightForRowCount(3))
                        .padding(.bottom, 16)
                        .padding(.top, -12)
                }
                toView
            }
        }
    }
    
    @ViewBuilder
    var toView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let text {
                Text(text)
                    .font17h22()
            }
            TappableAddress(account: AccountContext(source: .current), model: addressViewModel)
        }
    }
}
