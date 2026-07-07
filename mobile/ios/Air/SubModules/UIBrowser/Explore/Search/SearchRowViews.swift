import Kingfisher
import Perception
import SwiftUI
import UIComponents
import UIInAppBrowser
import WalletContext
import WalletCore

struct SearchSectionHeaderView: View {
    let header: SearchSectionHeader
    var hasTopGap: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text(header.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.air.secondaryLabel)

            if let action = header.action {
                Spacer(minLength: 8)
                Button(action: action.handler) {
                    Text(action.title)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.air.secondaryLabel)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: hasTopGap ? 16 : 0, leading: 12, bottom: 3, trailing: 12))
        .background(alignment: .bottom) {
            SearchRowSeparator(leadingPadding: 12)
        }
    }
}

struct SearchResultItemRow: View {
    let item: ExploreSearchResultItem
    let openAction: () -> ()

    var body: some View {
        let bottomPadding: CGFloat = if #available(iOS 26.0, *) { 9 } else { 10 }
        
        HStack(spacing: 8) {
            SearchResultItemIcon(item: item)

            SearchResultItemLabels(item: item)

            Spacer(minLength: 4)

            if item.showOpenButton {
                Button(action: openAction) {
                    Text(lang("Open"))
                    .foregroundStyle(.tint)
                }
                .buttonStyle(OpenButtonStyle(size: .small))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !item.showOpenButton { openAction() } }
        .padding(.top, 9)
        .padding(.bottom, bottomPadding)
        .padding(.horizontal, 12)
        .background(alignment: .bottom) {
            SearchRowSeparator(leadingPadding: 44)
        }
    }
}

struct SearchResultTopMatchItemRow: View {
    let item: ExploreSearchResultItem
    let tapAction: () -> ()

    var body: some View {
        let cornerRadius: CGFloat = 22
        
        Button(action: tapAction) {
            HStack(spacing: 8) {
                SearchResultItemIcon(item: item)
                SearchResultItemLabels(item: item)
                Spacer(minLength: 4)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.air.buttonBackground)
                    .padding(.horizontal, -4)
            }
            .contentShape(.rect(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

struct SuggestedSiteRow: View {
    let title: String
    let subtitle: String
    let url: String
    let iconName: String
    let openAction: () -> ()

    private let iconSize: CGFloat = 24
    private let iconCornerRadius: CGFloat = 6

    var body: some View {
        let bottomPadding: CGFloat = if #available(iOS 26.0, *) { 9 } else { 10 }

        HStack(spacing: 8) {
            Image.airBundle(iconName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(.rect(cornerRadius: iconCornerRadius))
                .frame(width: iconSize, height: iconSize)
                .applyModifierConditionally {
                    if #available(iOS 26.0, *) {
                        $0.glassEffect(.regular, in: .rect(cornerRadius: iconCornerRadius))
                    } else {
                        $0
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { openAction() }
        .padding(.top, 9)
        .padding(.bottom, bottomPadding)
        .padding(.horizontal, 12)
        .background(alignment: .bottom) {
            SearchRowSeparator(leadingPadding: 44)
        }
    }
}

struct WalletTopMatchRow: View {
    let chain: ApiChain
    let address: String
    let name: String?
    let domain: String?
    let tapAction: () -> ()

    private let iconSize: CGFloat = 24
    private let iconCornerRadius: CGFloat = 6
    private var hasFullInfo: Bool { name?.nilIfEmpty != nil }
    private var avatarAccount: MAccount {
        MAccount(id: "", title: name, type: .view, byChain: [chain: AccountChain(address: address)], isTemporary: true)
    }

    var body: some View {
        let cornerRadius: CGFloat = 22

        Button(action: tapAction) {
            HStack(spacing: 8) {
                icon
                labels
                Spacer(minLength: 4)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.air.buttonBackground)
                    .padding(.horizontal, -4)
            }
            .contentShape(.rect(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var icon: some View {
        if hasFullInfo {
            AccountIconView(account: avatarAccount, size: iconSize)
                .frame(width: iconSize, height: iconSize)
        } else {
            Image(uiImage: chain.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(.rect(cornerRadius: iconCornerRadius))
                .frame(width: iconSize, height: iconSize)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let name = name?.nilIfEmpty {
                Text(name)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                MiddleTruncatedText(
                    address,
                    font: .systemFont(ofSize: 17, weight: .medium),
                    separatorColor: .air.secondaryLabel
                )
            }

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.air.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var title: String {
        if let name = name?.nilIfEmpty {
            return name
        }
        return address
    }

    private var subtitle: String {
        guard hasFullInfo else {
            return chain.title
        }
        let shortAddress = formatStartEndAddress(address)
        if let domain = domain?.nilIfEmpty {
            return "\(domain) • \(shortAddress)"
        }
        return shortAddress
    }
}

struct MyWalletRow: View {
    let name: String?
    let address: String
    let isTopMatch: Bool
    let tapAction: () -> ()

    @State private var accountContext: AccountContext
    private let iconSize: CGFloat = 24

    init(account: MAccount, name: String?, address: String, isTopMatch: Bool, tapAction: @escaping () -> ()) {
        self.name = name
        self.address = address
        self.isTopMatch = isTopMatch
        self.tapAction = tapAction
        _accountContext = State(initialValue: AccountContext(accountId: account.id))
    }

    var body: some View {
        if isTopMatch {
            card
        } else {
            row
        }
    }

    private var card: some View {
        let cornerRadius: CGFloat = 22
        return Button(action: tapAction) {
            content
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.air.buttonBackground)
                        .padding(.horizontal, -4)
                }
                .contentShape(.rect(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private var row: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { tapAction() }
            .padding(.top, 9)
            .padding(.bottom, 10)
            .padding(.horizontal, 12)
            .background(alignment: .bottom) {
                SearchRowSeparator(leadingPadding: 44)
            }
    }

    private var content: some View {
        WithPerceptionTracking {
            HStack(spacing: 8) {
                AccountIconView(account: accountContext.account, size: iconSize)
                    .frame(width: iconSize, height: iconSize)
                labels
                Spacer(minLength: 4)
            }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            MtwCardAddressLine(addressLine: accountContext.addressLine, style: .search, gradient: nil)
                .foregroundStyle(Color.air.secondaryLabel)
                .lineLimit(1)
        }
    }

    private var title: String {
        if let name = name?.nilIfEmpty {
            return name
        }
        return address
    }
}

private struct AccountIconView: UIViewRepresentable {
    var account: MAccount?
    var size: CGFloat

    func makeUIView(context: Context) -> IconView {
        IconView(size: size)
    }

    func updateUIView(_ uiView: IconView, context: Context) {
        uiView.setSize(size)
        uiView.config(with: account)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: IconView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

private struct SearchResultItemLabels: View {
    let item: ExploreSearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(item.name)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                if item.shouldOpenExternally {
                    Image.airBundle("TelegramLogo20")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 18)
                        .foregroundStyle(Color.air.secondaryLabel.opacity(0.5))
                }
            }

            Text(item.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.air.secondaryLabel)
                .lineLimit(1)
        }
    }
}

private struct SearchResultItemIcon: View {
    let item: ExploreSearchResultItem

    private let iconSize: CGFloat = 24
    private let iconCornerRadius: CGFloat = 6

    var body: some View {
        if case .history = item.source, !item.showFavicon {
            Image(systemName: "clock")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.air.primaryLabel)
                .frame(width: iconSize, height: iconSize)
        } else {
            KFImage(URL(string: item.iconURL))
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
                .clipShape(.rect(cornerRadius: iconCornerRadius))
                .frame(width: iconSize, height: iconSize)
                .applyModifierConditionally {
                    if #available(iOS 26.0, *) {
                        $0.glassEffect(.regular, in: .rect(cornerRadius: iconCornerRadius))
                    } else {
                        $0
                    }
                }
        }
    }
}

struct RecentSearchItemRow: View {
    let text: String
    let isCompact: Bool
    var iconName: String = "magnifyingglass"
    let tapAction: () -> ()
    
    var body: some View {
        let padding: CGFloat = isCompact ? 0 : 3
        let extraPadding: CGFloat = if #available(iOS 26.0, *) { 4 } else { 0 }
        let iconSize: CGFloat = 24

        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.air.primaryLabel)
                .frame(width: iconSize, height: iconSize)

            Text(text)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.air.primaryLabel)
                .lineLimit(1)

            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { tapAction() }
        .padding(.top, 6 + extraPadding + padding)
        .padding(.bottom, 8 + extraPadding + padding)
        .padding(.horizontal, 12)
        .background(alignment: .bottom) {
            SearchRowSeparator(leadingPadding: 44)
        }
   
    }
}

struct SuggestedSearchItemRow: View {
    let text: String
    let visitDate: Date
    let tapAction: () -> ()

    var body: some View {
        let iconSize: CGFloat = 24
        let bottomPadding: CGFloat = if #available(iOS 26.0, *) { 9 } else { 10 }
        
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.air.primaryLabel)
                .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)

                Text(SearchDateFormatting.relativeString(for: visitDate))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { tapAction() }
        .padding(.top, 9)
        .padding(.bottom, bottomPadding)
        .padding(.horizontal, 12)
        .background(alignment: .bottom) {
            SearchRowSeparator(leadingPadding: 44)
        }
    }
}

private struct SearchRowSeparator: View {
    let leadingPadding: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
         if #available(iOS 26.0, *) {
             EmptyView()
         } else {
            Rectangle()
                .fill(Color.air.separator)
                .frame(height: 1 / max(displayScale, 1))
                .padding(.leading, leadingPadding)
                .padding(.trailing, 12)
         }
    }
}
