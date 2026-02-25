import SwiftUI
import UIComponents
import WalletContext
import Perception

@MainActor
@Perceptible
private final class InAppBrowserMinimizedViewModel {
    var title: String?
    var iconUrl: String?
    var titleTapAction: () -> ()
    var closeAction: () -> ()
    
    init(title: String?, iconUrl: String? = nil, titleTapAction: @escaping () -> Void, closeAction: @escaping () -> Void) {
        self.title = title
        self.iconUrl = iconUrl
        self.titleTapAction = titleTapAction
        self.closeAction = closeAction
    }
}

final class InAppBrowserMinimizedView: HostingView {
    
    private let viewModel: InAppBrowserMinimizedViewModel
    
    init(title: String?, iconUrl: String? = nil, titleTapAction: @escaping () -> Void, closeAction: @escaping () -> Void) {
        let viewModel = InAppBrowserMinimizedViewModel(title: title, iconUrl: iconUrl, titleTapAction: titleTapAction, closeAction: closeAction)
        self.viewModel = viewModel
        super.init {
            InAppBrowserMinimizedViewContent(viewModel: viewModel)
        }
    }

    func update(title: String?, iconUrl: String?) {
        viewModel.title = title
        viewModel.iconUrl = iconUrl
    }
}

private struct InAppBrowserMinimizedViewContent: View {
    
    var viewModel: InAppBrowserMinimizedViewModel
    
    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 4) {
                xMark
                titleView
                xMark
                    .hidden()
            }            
        }
    }
    
    @ViewBuilder
    var xMark: some View {
        Button(action: viewModel.closeAction) {
            Image.airBundle("MinimizedBrowserXMark24")
                .foregroundStyle(Color(WTheme.primaryLabel))
                .padding(10)
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
                    DappIcon(iconUrl: iconUrl)
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
            .contentShape(.rect)
        }
        .padding(.trailing, -30)
        .buttonStyle(.plain)
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    @Previewable let viewModel = InAppBrowserMinimizedViewModel(
        title: "Fragment",
        iconUrl: "https://static.mytonwallet.org/explore-icons/mtwcards.webp",
        titleTapAction: { },
        closeAction: { }
    )
    
    InAppBrowserMinimizedViewContent(viewModel: viewModel)
        .frame(height: 44)
        .aspectRatio(contentMode: .fit)
        .background(
            Color.blue.opacity(0.2)
        )
}
#endif
