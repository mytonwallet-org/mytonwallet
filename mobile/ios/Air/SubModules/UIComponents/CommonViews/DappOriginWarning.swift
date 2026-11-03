
import Foundation
import SwiftUI
import WalletContext
import WalletCore

@MainActor public func showDappOriginWarningTip(urlTrustStatus: ApiDappUrlTrustStatus = .unknown) {
    topWViewController()?.showTip(
        title: lang(urlTrustStatus.warningTitle),
        message: urlTrustStatus.warningText,
        kind: urlTrustStatus == .dangerous ? .danger : .warning
    )
}

public struct DappOriginWarning: View {

    public var urlTrustStatus: ApiDappUrlTrustStatus

    public init(urlTrustStatus: ApiDappUrlTrustStatus = .unknown) {
        self.urlTrustStatus = urlTrustStatus
    }

    public var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(urlTrustStatus.warningColor)
            .imageScale(.small)
            .textStyle(
                .bodyBold,
                content: .technical,
                scaling: .dynamic
            )
            .padding(10)
            .contentShape(.rect)
            .onTapGesture {
                showDappOriginWarningTip(urlTrustStatus: urlTrustStatus)
            }
            .padding(-10)
    }
}

private extension ApiDappUrlTrustStatus {
    var warningTitle: String {
        switch self {
        case .invalid:
            "DappurlTrustStatusInvalidTitle"
        case .dangerous:
            "DappurlTrustStatusDangerousTitle"
        case .verified, .unknown:
            "Unverified Source"
        }
    }

    var warningText: String {
        switch self {
        case .invalid:
            lang("$DappurlTrustStatusInvalidHelp")
        case .dangerous:
            lang("$DappurlTrustStatusDangerousHelp")
        case .verified, .unknown:
            L10n.reopenInIabExplore(exploreTab: lang("Explore"))
        }
    }

    var warningColor: Color {
        self == .dangerous ? Color.air.error : .orange
    }

}
