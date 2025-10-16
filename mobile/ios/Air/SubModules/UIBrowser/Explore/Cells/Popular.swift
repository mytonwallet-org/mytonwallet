
import Kingfisher
import SwiftUI
import WalletCore
import WalletContext


struct DappCell: View {
    
    var item: ApiSite
    
    var isHighlighted: Bool
    
    private let borderWidth: CGFloat = 4
    
    var body: some View {
        let url: URL? = URL(string: item.icon)
        ZStack(alignment: .leading) {
            Color.clear
            KFImage(url)
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
        }
        .overlay {
            if item.withBorder == true {
                ContainerRelativeShape()
                    .stroke(Color(WTheme.tint), lineWidth: borderWidth)
            }
        }
        .highlightOverlay(isHighlighted)
        .clipShape(.rect(cornerRadius: 16))
        .containerShape(.rect(cornerRadius: 16))
    }
}

struct MoreItemsCell: View {
    
    var items: [ApiSite]
    
    var isHighlighted: Bool
    
    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                preview(0)
                preview(1)
            }
            GridRow {
                preview(2)
                preview(3)
            }
        }
    }
    
    @ViewBuilder
    func preview(_ idx: Int) -> some View {
        if idx < items.count, let url = URL(string: items[idx].icon) {
            KFImage(url)
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fit)
                .highlightOverlay(isHighlighted)
                .clipShape(.rect(cornerRadius: 7))
        } else {
            Color.clear
        }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 16) {
        DappCell(item: .sampleFeaturedTelegram, isHighlighted: false)
            .frame(width: 100, height: 100)
        
        MoreItemsCell(items: [.sampleFeaturedTelegram, .sampleFeaturedTelegram, .sampleFeaturedTelegram], isHighlighted: false)
            .frame(width: 100, height: 100)
    }
    .padding(.horizontal, 20)
}
#endif
