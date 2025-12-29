
import SwiftUI
import UIComponents
import WalletContext
import Kingfisher

private let extraPadding: CGFloat = 10

@MainActor
final class MinimizedSheetViewModel: ObservableObject {
    @Published var title: String?
    @Published var iconUrl: String?
    @Published var titleTapAction: () -> ()
    @Published var closeAction: () -> ()
    
    init(title: String?, iconUrl: String? = nil, titleTapAction: @escaping () -> Void, closeAction: @escaping () -> Void) {
        self.title = title
        self.iconUrl = iconUrl
        self.titleTapAction = titleTapAction
        self.closeAction = closeAction
    }
}

final class MinimizedSheetView: HostingView {
    
    var viewModel: MinimizedSheetViewModel
    
    init(title: String?, iconUrl: String? = nil, titleTapAction: @escaping () -> Void, closeAction: @escaping () -> Void) {
        let viewModel = MinimizedSheetViewModel(title: title, iconUrl: iconUrl, titleTapAction: titleTapAction, closeAction: closeAction)
        self.viewModel = viewModel
        super.init {
            _MinimizedSheetView(viewModel: viewModel)
        }
    }
}

struct _MinimizedSheetView: View {
    
    @ObservedObject var viewModel: MinimizedSheetViewModel
    
    var body: some View {
        HStack(spacing: 4) {
            xMark
            titleView
            xMark
                .hidden()
        }
        
    }
    
    @ViewBuilder
    var xMark: some View {
        Button(action: viewModel.closeAction) {
            Image.airBundle("MinimizedBrowserXMark24")
                .foregroundStyle(Color(WTheme.primaryLabel))
                .padding(10)
//                .border(Color.red)
.contentShape(.containerRelative)
                .containerShape(.rect)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    var titleView: some View {
        Button(action: viewModel.titleTapAction) {
            HStack(spacing: 8) {
                if let iconUrl = viewModel.iconUrl {
                    KFImage(URL(string: iconUrl))
                        .placeholder {
                            Color(WTheme.secondaryFill)
                        }
                        .resizable()
                        .loadDiskFileSynchronously(false)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(.rect(cornerRadius: 8))
                        .padding(.leading, -2)
                }
                Text(viewModel.title?.nilIfEmpty ?? " ")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(WTheme.primaryLabel))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.trailing, 30)
//            .border(Color.red)
            .contentShape(.rect)
        }
        .padding(.trailing, -30)
        .buttonStyle(.plain)
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable let viewModel = MinimizedSheetViewModel(
        title: "Fragment",
        iconUrl: "https://static.mytonwallet.org/explore-icons/mtwcards.webp",
        titleTapAction: { },
        closeAction: { }
    )
    
    _MinimizedSheetView(viewModel: viewModel)
        .frame(height: 44)
        .aspectRatio(contentMode: .fit)
        .background(
            Color.blue.opacity(0.2)
        )
}
#endif
