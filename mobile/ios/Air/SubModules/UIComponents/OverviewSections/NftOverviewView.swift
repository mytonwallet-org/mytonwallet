
import SwiftUI
import WalletContext
import WalletCore


public struct NftOverviewView: View {
    
    var nft: ApiNft
    var isOutgoing: Bool
    var text: String?
    var addressName: String?
    var addressOrDomain: String
    
    public init(nft: ApiNft, isOutgoing: Bool, text: String? = nil, addressName: String? = nil, addressOrDomain: String) {
        self.nft = nft
        self.isOutgoing = isOutgoing
        self.text = text
        self.addressName = addressName
        self.addressOrDomain = addressOrDomain
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            NftImage(nft: nft, animateIfPossible: false)
                .frame(width: 144, height: 144)
                .clipShape(.rect(cornerRadius: 12))
                .padding(.bottom, 16)
                .padding(.top, -12)
            toView
        }
    }
    
    @ViewBuilder
    var toView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let text {
                Text(text)
                    .font17h22()
            }
            TappableAddress(account: AccountContext(source: .current), name: addressName, chain: "ton", addressOrName: addressOrDomain)
        }
    }
}
