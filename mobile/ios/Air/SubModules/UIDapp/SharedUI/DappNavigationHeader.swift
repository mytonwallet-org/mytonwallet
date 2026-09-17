import Perception
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

final class DappNavigationHeader: HostingView {
    init(accountContext: AccountContext, dapp: ApiDapp?, request: ApiUpdate.DappSendTransactions? = nil) {
        super.init {
            DappNavigationHeaderContent(accountContext: accountContext, dapp: dapp, request: request)
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44)
    }
}

private struct DappNavigationHeaderContent: View {
    let accountContext: AccountContext
    let dapp: ApiDapp?
    let request: ApiUpdate.DappSendTransactions?

    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 8) {
                accountPill
                    .layoutPriority(1)

                Image.airBundle("DappHeaderConnection")
                    .resizable(resizingMode: .tile)
                    .foregroundStyle(Color.air.separator)
                    .frame(minWidth: 12, maxWidth: .infinity)
                    .frame(height: 1.2)
                    .accessibilityHidden(true)

                dappPill
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .skeletonContainer(isActive: dapp == nil)
        }
    }

    private var accountPill: some View {
        HStack(spacing: 6) {
            AccountIcon(account: accountContext.account, size: 32, initialsFontSize: 13)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                balance
                    .frame(height: 16)
                Text(accountContext.account.displayName)
                    .textStyle(.caption)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 16)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background(Color.air.secondaryLabel.opacity(0.1), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var balance: some View {
        if let request {
            let display = request.tokenToDisplay(accountContext: accountContext)
            AmountText(
                amount: TokenAmount(display.balance, display.token).roundedForDisplay,
                format: .init(),
                integerFont: .systemFont(ofSize: 14, weight: .semibold),
                fractionFont: .systemFont(ofSize: 12, weight: .medium),
                symbolFont: .systemFont(ofSize: 12, weight: .medium),
                integerColor: .label,
                fractionColor: .label,
                symbolColor: .label
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text(accountContext.balance?.formatted(.baseCurrencyEquivalent) ?? "—")
                .textStyle(.supportingStrong, content: .technical)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var dappPill: some View {
        if let dapp, dapp.shouldShowUrlTrustStatusWarning {
            Button {
                showDappOriginWarningTip(urlTrustStatus: dapp.resolvedUrlTrustStatus)
            } label: {
                dappContent(dapp)
            }
            .buttonStyle(.plain)
        } else {
            dappContent(dapp ?? .loadingStub)
        }
    }

    private func dappContent(_ dapp: ApiDapp) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(dapp.name)
                    .textStyle(.supportingStrong)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 16)
                    .skeletonPlaceholder(surface: .dark)
                HStack(spacing: 4) {
                    Text(dapp.displayUrl)
                        .textStyle(.caption, content: .technical)
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .skeletonPlaceholder(surface: .dark)
                    if self.dapp != nil, dapp.shouldShowUrlTrustStatusWarning {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(dapp.resolvedUrlTrustStatus == .dangerous ? Color.air.error : .orange)
                            .accessibilityLabel(lang(dapp.resolvedUrlTrustStatus == .dangerous ? "DappurlTrustStatusDangerousTitle" : "Unverified Source"))
                    }
                }
                .frame(height: 16)
            }
            DappIcon(iconUrl: dapp.iconUrl)
                .frame(width: 32, height: 32)
                .clipShape(.circle)
                .skeletonPlaceholder(surface: .dark, cornerRadius: 16)
                .accessibilityHidden(true)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 44)
        .background(Color.air.secondaryLabel.opacity(0.1), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
