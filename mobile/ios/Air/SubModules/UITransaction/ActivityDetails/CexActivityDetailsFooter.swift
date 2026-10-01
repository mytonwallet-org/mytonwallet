import SwiftUI
import WalletContext
import WalletCore

struct CexActivityDetailsFooter: View {
    let swap: ApiSwapActivity
    let date: Date

    private var status: SwapDisplayStatus { swap.displayStatus(at: date) }

    private var statusMessage: String? {
        switch status {
        case .pending, .waitingForPayment:
            lang("Please note that it may take up to a few hours for tokens to appear in your wallet.")
        case .expired:
            lang("You have not sent the coins to the specified address.")
        case .refunded:
            lang("Exchange failed and coins were refunded to your wallet.")
        case .hold, .failed, .completed:
            nil
        }
    }

    var body: some View {
        if swap.cex != nil, statusMessage != nil || supportMessage != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(status.isError ? Color.air.error : Color.air.secondaryLabel)
                }
                if let supportMessage {
                    Text(supportMessage)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var supportMessage: AttributedString? {
        guard swap.shouldShowCexSupport(at: date),
              let cex = swap.cex,
              let provider = cex.providerName?.nilIfEmpty else {
            return nil
        }
        let supportUrl = URL.sanitizedHttpUrl(from: cex.supportUrl)
        let emailLink = URL.sanitizedMailtoLink(email: cex.supportEmail)
        guard supportUrl != nil || emailLink != nil else { return nil }
        let label = L10n.swapCexProviderSupport(provider: provider)
        let text: String
        if let emailLink {
            text = status == .hold
                ? L10n.swapCexHoldSupportFooterEmail(support: label, email: emailLink.email)
                : L10n.swapCexSupportFooterEmail(support: label, email: emailLink.email)
        } else {
            text = status == .hold
                ? L10n.swapCexHoldSupportFooter(support: label)
                : L10n.swapCexSupportFooter(support: label)
        }
        var message = AttributedString(text)
        if let range = message.range(of: label) {
            message[range].link = supportUrl ?? emailLink?.url
        }
        if let emailLink, let range = message.range(of: emailLink.email) {
            message[range].link = emailLink.url
        }
        return message
    }
}
