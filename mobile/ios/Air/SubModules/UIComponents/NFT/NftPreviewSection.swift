import SwiftUI
import WalletCore

public struct NftPreviewSection: View {
    private let nfts: [ApiNft]
    private let maxItems: Int
    private let maxRows: Int

    public init(
        nfts: [ApiNft],
        maxItems: Int = 10,
        maxRows: Int = 6
    ) {
        self.nfts = nfts
        self.maxItems = maxItems
        self.maxRows = maxRows
    }

    public var body: some View {
        if !nfts.isEmpty {
            InsetSection {
                if nfts.count == 1 {
                    NftPreviewRow(nft: nfts[0])
                } else {
                    InsetCell(verticalPadding: 16) {
                        NftPreviewFlowRepresentable(
                            nfts: nfts,
                            maxItems: maxItems,
                            maxRows: maxRows
                        )
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
