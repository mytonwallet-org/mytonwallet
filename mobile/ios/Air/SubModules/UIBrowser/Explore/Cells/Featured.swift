
import Kingfisher
import SwiftUI
import WalletCore
import WalletContext

struct FeaturedDappCell: View {
    
    var item: ApiSite
    
    var isHighlighted: Bool
    
    var openAction: () -> ()
    
    private let borderWidth: CGFloat = 4
    
    var body: some View {
        let url: URL? = if let expanded = item.extendedIcon { URL(string: expanded) } else { URL(string: item.icon) }
        ZStack(alignment: .top) {
            Color.clear
            VStack(spacing: 0) {
                KFImage(url)
                    .resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(contentMode: .fill)
                KFImage(url)
                    .resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(y: -1)
                    .zIndex(-1)
            }
        }
        .frame(height: 220, alignment: .top)
        .overlay(alignment: .bottom) {
            overlayContent
        }
//        .border(Color.red, width: 4)
        .contentShape(.containerRelative)
        .highlightOverlay(isHighlighted)
        .clipShape(.containerRelative)
        .containerShape(.rect(cornerRadius: 14))
    }
    
    @ViewBuilder
    var overlayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
//            titleLabels
            openSection
        }
        .environment(\.colorScheme, .light)
    }
    
    @ViewBuilder
    var titleLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kicker = item.test_kicker {
                Text(kicker)
                    .textCase(.uppercase)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Material.thin)
            }
            Text(item.test_shortTitle)
                .font(.system(size: 29, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    var openSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                KFImage(URL(string: item.icon))
                    .resizable()
                    .loadDiskFileSynchronously(false)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 11))
                    .padding(.trailing, 10)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(item.description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Material.thin)
                        .lineLimit(2)
                }
                .padding(.trailing, 8)
                
                Spacer(minLength: 0)
                
                Button(action: openAction) {
                    Text(lang("Open"))
                }
                .buttonStyle(OpenButtonStyle())
            }
                
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            Rectangle()
                .fill(Material.thin)
                .environment(\.colorScheme, .dark)
        }
    }
}

fileprivate struct OpenButtonStyle: PrimitiveButtonStyle {
    @State private var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .opacity(isHighlighted ? 0.5 : 1)
            .foregroundStyle(Color(WTheme.tint))
            .background(.white.opacity(0.5).blendMode(.overlay), in: .containerRelative)
            .contentShape(.containerRelative.inset(by: -10))
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
            .containerShape(.capsule)
    }
}

#if DEBUG
#Preview {
    FeaturedDappCell(item: .sampleFeaturedTelegram, isHighlighted: false, openAction: {})
        .padding(.horizontal, 20)
}
#endif
