import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let changellyWaitingDeadline: TimeInterval = 3 * 60 * 60
private let changellySupportEmail = "support@changelly.com"
private let changellyLiveChatURL = "https://changelly.com/"

struct CrosschainToWalletPayment: Equatable {
    let sellingAmount: TokenAmount
    let buyingAmount: TokenAmount
    let payinAddress: String
    let payoutAddress: String
    let payinExtraId: String?
    let exchangerTxId: String
    let createdAt: Date
    let cexStatus: ApiSwapCexTransactionStatus?
    let isInternalSwap: Bool

    var sellingToken: ApiToken {
        sellingAmount.type
    }

    var amount: Double {
        sellingAmount.amount.doubleAbsRepresentation(decimals: sellingAmount.decimals)
    }

    var expireDate: Date {
        createdAt.addingTimeInterval(changellyWaitingDeadline)
    }

    var hasMemo: Bool {
        payinExtraId?.nilIfEmpty != nil
    }

    var transferUrl: String {
        sellingToken.chain.config.formatTransferUrl?(payinAddress, nil, nil, nil) ?? payinAddress
    }

    func isExpired(at date: Date) -> Bool {
        if cexStatus?.uiStatus == .expired {
            return true
        }
        return canExpireByTime && expireDate <= date
    }

    func showsPaymentInstructions(at date: Date) -> Bool {
        !isInternalSwap && !isExpired(at: date) && isWaitingForPayment && !payinAddress.isEmpty
    }

    func shouldShowQRCode(at date: Date) -> Bool {
        showsPaymentInstructions(at: date) && !hasMemo
    }

    private var canExpireByTime: Bool {
        switch cexStatus {
        case nil, .new, .waiting, .pending:
            return true
        case .confirming, .exchanging, .sending, .finished, .failed, .refunded, .hold, .overdue, .expired, .confirmed:
            return false
        }
    }

    private var isWaitingForPayment: Bool {
        switch cexStatus {
        case nil, .new, .waiting, .pending:
            return true
        case .confirming, .exchanging, .sending, .finished, .failed, .refunded, .hold, .overdue, .expired, .confirmed:
            return false
        }
    }
}

struct CrosschainToWalletView: View {
    let payment: CrosschainToWalletPayment
    var onExpired: () -> Void = {}

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()

    var body: some View {
        section
            .onAppear {
                notifyIfExpired()
            }
            .onReceive(timer) { date in
                now = date
                notifyIfExpired()
            }
    }

    @ViewBuilder
    private var section: some View {
        if payment.showsPaymentInstructions(at: now) {
            InsetSection(addDividers: false) {
                paymentInstructions
            } header: {
                paymentHeader
            } footer: {
                footer
            }
        } else {
            InsetSection(addDividers: false) {
                statusContent
            }
        }
    }

    private var paymentHeader: some View {
        Text(
            lang(
                "$swap_changelly_to_wallet_description1",
                arg1: DecimalAmount.fromDouble(payment.amount, payment.sellingToken).formatted(.none),
                arg2: payment.sellingToken.chain.config.title,
                arg3: remainingText
            )
        )
    }

    private var paymentInstructions: some View {
        VStack(spacing: 14) {
            amountView
                .padding(.top, 16)
            copyableField(
                label: lang("Address for %blockchain% transfer", arg1: payment.sellingToken.chain.config.title),
                value: payment.payinAddress,
                copyMessage: lang("%chain% Address Copied", arg1: payment.sellingToken.chain.title),
                isCentered: true
            )
            if let memo = payment.payinExtraId?.nilIfEmpty {
                copyableField(
                    label: lang("Memo"),
                    value: memo,
                    copyMessage: lang("Memo Copied"),
                    isCentered: true
                )
            }
            if payment.shouldShowQRCode(at: now) {
                qr
                    .padding(.bottom, 16)
            } else {
                Color.clear
                    .frame(height: 2)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var statusContent: some View {
        if payment.isExpired(at: now) {
            expiredContent
        } else if payment.isInternalSwap {
            internalSwapContent
        } else {
            inProgressContent
        }
    }

    private var expiredContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(lang("The time for sending coins is over."))
                    .font(.system(size: 17, weight: .semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.air.error)
            }
            supportText
            transactionID
        }
        .padding(16)
    }

    private var internalSwapContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lang("Please note that it may take up to a few hours for tokens to appear in your wallet."))
                .foregroundStyle(Color.air.secondaryLabel)
            transactionID
        }
        .padding(16)
    }

    private var inProgressContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lang("Please note that it may take up to a few hours for tokens to appear in your wallet."))
                .foregroundStyle(Color.air.secondaryLabel)
            transactionID
        }
        .padding(16)
    }

    private var amountView: some View {
        HStack(spacing: 2) {
            Image(systemName: "clock.fill")
                .imageScale(.small)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.air.secondaryLabel)
            AmountText(
                amount: DecimalAmount.fromDouble(payment.amount, payment.sellingToken),
                format: .init(),
                integerFont: .systemFont(ofSize: 17, weight: .semibold),
                fractionFont: .systemFont(ofSize: 17, weight: .semibold),
                symbolFont: .systemFont(ofSize: 17, weight: .semibold),
                integerColor: UIColor.label,
                fractionColor: UIColor.label,
                symbolColor: .air.secondaryLabel
            )
        }
    }

    private var qr: some View {
        WUIQRCodeContainerView(
            url: payment.transferUrl,
            imageURL: payment.sellingToken.image ?? "",
            size: 262,
            onTap: shareQRCode
        )
        .frame(width: 262, height: 262, alignment: .leading)
        .padding(.leading, 6)
        .padding(4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lang("Please note that it may take up to a few hours for tokens to appear in your wallet."))
                .padding(.top, 13)
            transactionID
        }
    }

    @ViewBuilder
    private var transactionID: some View {
        if !payment.exchangerTxId.isEmpty {
            copyableField(
                label: lang("Transaction ID"),
                value: payment.exchangerTxId,
                copyMessage: lang("Transaction ID Copied"),
                isCentered: false
            )
        }
    }

    private var supportText: some View {
        let supportRaw = lang(
            "$swap_changelly_support",
            arg1: lang("Changelly Live Chat"),
            arg2: changellySupportEmail
        )
        let parsed = (try? NSAttributedString(markdown: supportRaw)) ?? NSAttributedString(string: supportRaw)
        let attr = NSMutableAttributedString(attributedString: parsed)
        let fullRange = NSRange(location: 0, length: attr.length)
        attr.addAttributes([
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.air.secondaryLabel
        ], range: fullRange)

        addLink(
            to: attr,
            text: lang("Changelly Live Chat"),
            url: changellyLiveChatURL
        )
        addLink(
            to: attr,
            text: changellySupportEmail,
            url: "mailto:\(changellySupportEmail)"
        )
        let transactionIdRange = (attr.string as NSString).range(of: lang("Transaction ID"))
        if transactionIdRange.location != NSNotFound {
            attr.addAttribute(.font, value: UIFont.systemFont(ofSize: 13, weight: .semibold), range: transactionIdRange)
        }

        return Text(attr)
            .lineSpacing(3)
    }

    private var remainingText: String {
        Duration.seconds(max(0, payment.expireDate.timeIntervalSince(now)))
            .formatted(
                Duration.UnitsFormatStyle(
                    allowedUnits: [.days, .hours, .minutes, .seconds],
                    width: .wide,
                    maximumUnitCount: 2,
                    zeroValueUnits: .hide,
                    fractionalPart: .hide
                )
                .locale(LocalizationSupport.shared.locale)
            )
    }

    private func copyableField(
        label: String,
        value: String,
        copyMessage: String,
        isCentered: Bool
    ) -> some View {
        let alignment: HorizontalAlignment = isCentered ? .center : .leading
        return VStack(alignment: alignment, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.air.secondaryLabel)
            Button {
                copy(value, message: copyMessage)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(address: value)
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(2)
                    Image("HomeCopy", bundle: AirBundle)
                        .foregroundColor(.air.secondaryLabel)
                }
                .multilineTextAlignment(isCentered ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
    }

    private func notifyIfExpired() {
        guard payment.isExpired(at: now) else { return }
        onExpired()
    }

    private func copy(_ value: String, message: String) {
        UIPasteboard.general.string = value
        AppActions.showToast(animationName: "Copy", message: message)
        Haptics.play(.lightTap)
    }

    private func addLink(to attr: NSMutableAttributedString, text: String, url: String) {
        let range = (attr.string as NSString).range(of: text)
        guard range.location != NSNotFound else { return }
        attr.addAttribute(.foregroundColor, value: UIColor.tintColor, range: range)
        attr.addAttribute(.font, value: UIFont.systemFont(ofSize: 13, weight: .semibold), range: range)
        attr.addAttribute(.link, value: url, range: range)
    }

    private func shareQRCode() {
        guard let (_, generator) = generateQrCode(
            string: payment.transferUrl,
            color: .black,
            backgroundColor: .white,
            icon: .custom(.airBundleOptional("chain_\(payment.sellingToken.chain.rawValue)"))
        ) else { return }
        
        let imageSize = CGSize(width: 768.0, height: 768.0)
        let context = generator(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: UIEdgeInsets(), scale: 1.0))
        guard let qrImage = context?.generateImage() else { return }
        
        guard let topVC = topViewController() else { return }
        let activityController = UIActivityViewController(activityItems: [qrImage], applicationActivities: nil)
        topVC.presentActivityViewController(activityController)
    }
}
