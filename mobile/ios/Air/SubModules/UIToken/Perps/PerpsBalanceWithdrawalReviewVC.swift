import Perception
import ProtectedAction
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// An adapter-owned withdrawal quote, already validated for review. The strings are display-ready.
public struct PerpsBalanceWithdrawalReviewDisplayData: PerpsReviewData {
    public var token: ApiToken
    public var receiveAmount: String
    public var amount: String
    public var fee: String
    public var bridgeFee: String
    public var firstTransferFee: String?
    public var destination: String
    public var status: PerpsOrderReviewDisplayData.Status = .ready
    public var notice: String?

    public init(token: ApiToken, receiveAmount: String, amount: String, fee: String, bridgeFee: String, firstTransferFee: String? = nil,
                destination: String) {
        self.token = token
        self.receiveAmount = receiveAmount
        self.amount = amount
        self.fee = fee
        self.bridgeFee = bridgeFee
        self.firstTransferFee = firstTransferFee
        self.destination = destination
    }

    var feeRows: [PerpsFeeRow] {
        var rows = [PerpsFeeRow(id: "bridge", title: lang("PerpsBridgeFee"), value: bridgeFee)]
        if let firstTransferFee {
            rows.append(.init(id: "firstTransfer", title: lang("PerpsFirstWithdrawalFee"), value: firstTransferFee))
        }
        return rows
    }
}

@MainActor
public final class PerpsBalanceWithdrawalReviewVC: WViewController {
    private let state: PerpsReviewState<PerpsBalanceWithdrawalReviewDisplayData>

    public init(data: PerpsBalanceWithdrawalReviewDisplayData, onConfirm: @escaping (PerpsOrderReviewRequest) -> Void) {
        state = PerpsReviewState(data: data, onConfirm: onConfirm)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// While confirmation is pending, echo its request.
    @discardableResult
    public func update(data: PerpsBalanceWithdrawalReviewDisplayData, for request: PerpsOrderReviewRequest? = nil) -> Bool {
        state.update(data: data, for: request)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("PerpsBalanceWithdrawalTitle")
        view.backgroundColor = .air.headerBackground
        configureNavigationItemWithTransparentBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.navigationController?.dismiss(animated: true)
        })
        let content = addHostingController(PerpsBalanceWithdrawalReviewView(state: state))
        let footer = addHostingController(PerpsBalanceWithdrawalReviewFooter(state: state))
        AssetDetailsView.prepare(content)
        AssetDetailsView.prepare(footer)
        AssetDetailsView(sections: [content.view], footer: footer.view, background: .air.headerBackground).install(in: view)
        addCustomNavigationBarBackground(color: .air.headerBackground)
    }
}

/// The reviewed withdrawal shown above ProtectedAction's authentication.
public struct PerpsBalanceWithdrawalConfirmationHeader: ConfirmationContent {
    public let data: PerpsBalanceWithdrawalReviewDisplayData

    public init(data: PerpsBalanceWithdrawalReviewDisplayData) { self.data = data }

    public var body: some View {
        PerpsBalanceWithdrawalSummaryView(data: data, accessibilityPrefix: "perps.withdrawal.authentication")
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, minHeight: 238)
    }

    public var compactRepresentation: some View {
        HStack(spacing: 12) {
            TokenHeroView(token: data.token, size: 48, shouldShowChain: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(lang("You Receive")).textStyle(.bodyStrong)
                Text(verbatim: data.receiveAmount).textStyle(.body, content: .technical)
            }
            Spacer(minLength: 0)
        }
    }
}

struct PerpsBalanceWithdrawalReviewView: View {
    let state: PerpsReviewState<PerpsBalanceWithdrawalReviewDisplayData>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 20) {
                PerpsBalanceWithdrawalSummaryView(data: state.data, accessibilityPrefix: "perps.withdrawal")
                PerpsBalanceWithdrawalDetailsSection(data: state.data, note: lang("PerpsBalanceWithdrawalNote"))
                if case .unavailable(let message) = state.data.status {
                    TradeNoticeView(title: "", message: message, isWarning: true)
                        .accessibilityIdentifier("perps.withdrawal.unavailable")
                } else if let notice = state.data.notice {
                    TradeNoticeView(title: "", message: notice, isWarning: false)
                        .accessibilityIdentifier("perps.withdrawal.updated")
                }
            }
            .padding(.bottom, 4)
        }
    }
}

struct PerpsBalanceWithdrawalReviewFooter: View {
    let state: PerpsReviewState<PerpsBalanceWithdrawalReviewDisplayData>

    var body: some View {
        WithPerceptionTracking {
            TradeContinueButton(configuration: .init(title: .text(lang("Confirm")), isEnabled: state.canConfirm,
                                                      showLoading: state.data.status == .loading),
                                tintColor: AirTintColor, accessibilityIdentifier: "perps.withdrawal.confirm") {
                state.confirm()
            }
            .frame(height: 52)
        }
    }
}

/// What leaves Hyperliquid, what it costs and where it goes, on the review and on the receipt.
struct PerpsBalanceWithdrawalDetailsSection: View {
    let data: PerpsBalanceWithdrawalReviewDisplayData
    let note: String?

    var body: some View {
        InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
            AssetInfoMetricRow(title: lang("PerpsWithdrawalFromHyperliquid"), value: data.amount)
            PerpsFeeSummaryRow(fee: data.fee, rows: data.feeRows)
            AssetInfoMetricRow(title: lang("PerpsWithdrawalToWallet"), value: data.destination)
        }
        if let note {
            Text(note)
                .textStyle(.footnote)
                .foregroundStyle(Color.air.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("perps.withdrawal.note")
        }
    }
}

struct PerpsBalanceWithdrawalSummaryView: View {
    let data: PerpsBalanceWithdrawalReviewDisplayData
    var showsCaption = true
    let accessibilityPrefix: String

    var body: some View {
        VStack(spacing: 16) {
            TokenHeroView(token: data.token, size: 80, shouldShowChain: false)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                if showsCaption {
                    Text(lang("You Receive"))
                        .textStyle(.subheadlineStrong)
                        .foregroundStyle(Color.air.secondaryLabel)
                }
                Text(verbatim: data.receiveAmount)
                    .textStyle(.screenTitle, content: .technical)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier(accessibilityPrefix + ".receive")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
