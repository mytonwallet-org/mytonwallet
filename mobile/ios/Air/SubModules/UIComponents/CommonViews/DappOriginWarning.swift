
import Foundation
import SwiftUI
import WalletContext
import WalletCore

@MainActor public func showDappOriginWarningTip(urlTrustStatus: ApiDappUrlTrustStatus = .unknown) {
    topWViewController()?.showTip(
        title: lang(urlTrustStatus.warningTitle),
        kind: urlTrustStatus == .dangerous ? .danger : .warning
    ) {
        Text(urlTrustStatus.warningText)
            .multilineTextAlignment(.center)
    }
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
            .fontWeight(.bold)
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

    var warningText: LocalizedStringKey {
        switch self {
        case .invalid:
            LocalizedStringKey(lang("$DappurlTrustStatusInvalidHelp"))
        case .dangerous:
            LocalizedStringKey(lang("$DappurlTrustStatusDangerousHelp"))
        case .verified, .unknown:
            langMd("$reopen_in_iab_explore", arg1: lang("Explore"))
        }
    }

    var warningColor: Color {
        self == .dangerous ? Color.air.error : .orange
    }

}
