
import Kingfisher
import SwiftUI
import WalletCore
import WalletContext


public struct NftPreviewRow: View {
    
    public var nft: ApiNft
    public var horizontalPadding: CGFloat?
    public var verticalPadding: CGFloat?
    
    public init(nft: ApiNft, horizontalPadding: CGFloat? = nil, verticalPadding: CGFloat? = nil) {
        self.nft = nft
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }
    
    public var body: some View {
        InsetCell(horizontalPadding: horizontalPadding, verticalPadding: verticalPadding) {
            HStack(spacing: 10) {
                image
                VStack(alignment: .leading, spacing: 0) {
                    Text(nft.name ?? "NFT")
                        .font17h22()
                        .lineLimit(1)
                    Text(nft.collectionName ?? lang("Standalone NFT"))
                        .font13()
                        .padding(.bottom, 2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    var image: some View {
        if let thumbnail = nft.thumbnail {
            KFImage(URL(string: thumbnail))
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(8)
                .frame(width: 64, height: 64)
        }
    }
}
