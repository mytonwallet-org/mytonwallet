
import SwiftUI
import WalletCore
import WalletContext


public struct NftPreviewRow: View {
    
    public static let thumbnailSize: CGFloat = 64
    public static let thumbnailCornerRadius: CGFloat = 8
    public static let contentSpacing: CGFloat = 10
    public static let defaultHorizontalPadding: CGFloat = 12
    public static let textLeadingInset: CGFloat = defaultHorizontalPadding + thumbnailSize + contentSpacing
    
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
            HStack(spacing: Self.contentSpacing) {
                image
                VStack(alignment: .leading, spacing: 0) {
                    Text(nft.displayName)
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
    
    var image: some View {
        NftImage(nft: nft, animateIfPossible: false)
            .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
            .background(Color.air.thumbBackground)
            .clipShape(RoundedRectangle(cornerRadius: Self.thumbnailCornerRadius, style: .continuous))
    }
}
