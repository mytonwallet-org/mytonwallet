import UIKit
import WalletContext
import WalletCore

/// One futures trade as listed in the account and market activity.
public struct PerpsTradeActivity: Identifiable {
    private enum DateValue {
        case text(String)
        case timestamp(Date)
    }

    public let id: String
    public var event: ApiPerpsFillEvent
    public var title: String
    /// Direction with the leverage the trade used, when the venue reports it.
    public var badge: String
    private let dateValue: DateValue
    public var date: String { formatDate(relativeTo: .now) }
    public var amount: PerpsValue
    public var detail: String
    /// An order that failed, which made no trade.
    public private(set) var isFailed = false

    public init(id: String, event: ApiPerpsFillEvent, title: String, badge: String, date: String,
                amount: PerpsValue, detail: String) {
        self.id = id
        self.event = event
        self.title = title
        self.badge = badge
        self.dateValue = .text(date)
        self.amount = amount
        self.detail = detail
    }

    public init(fill: ApiPerpsFill, asset: ApiPerpsAsset) {
        let symbol = asset.symbol
        id = fill.id
        event = fill.eventKind
        title = switch fill.eventKind {
        case .opened: L10n.perpsActivityOpened(asset: symbol)
        case .increased: L10n.perpsActivityIncreased(asset: symbol)
        case .reduced: L10n.perpsActivityReduced(asset: symbol)
        case .closed: L10n.perpsActivityClosed(asset: symbol)
        case .liquidated: L10n.perpsActivityLiquidated(asset: symbol)
        }
        badge = Self.badge(side: fill.positionSide, leverage: fill.leverage)
        // The venue records traded notional, but not the collateral a past trade added.
        amount = fill.eventKind.realizesProfitLoss ? PerpsFormatting.profitLoss(fill.netPnl) : .init(PerpsFormatting.money(fill.notional))
        detail = lang(fill.eventKind.realizesProfitLoss ? "Profit and Loss" : "Trade Size")
        dateValue = .timestamp(Date(timeIntervalSince1970: Double(fill.time) / 1000))
    }

    /// Hyperliquid keeps no record of a failed order, so its row comes from the operation this device submitted.
    public init(failedOrder operation: ApiPerpsOperation, asset: ApiPerpsAsset) {
        id = Self.failedOrderPrefix + operation.id
        event = switch operation.kind {
        case "open": .opened
        case "increase": .increased
        case "close": .closed
        default: .reduced
        }
        title = PerpsFormatting.operationTitle(operation, symbol: asset.symbol)
        badge = operation.reviewedQuote.map { Self.badge(side: $0.side, leverage: $0.leverage) } ?? ""
        amount = .init(lang("Failed"), tone: .negative)
        detail = ""
        dateValue = .timestamp(Date(timeIntervalSince1970: Double(operation.createdAt) / 1000))
        isFailed = true
    }

    /// The operation behind a row of `init(failedOrder:asset:)`.
    public static func failedOrderOperationID(activityID: String) -> String? {
        activityID.hasPrefix(failedOrderPrefix) ? String(activityID.dropFirst(failedOrderPrefix.count)) : nil
    }

    private static let failedOrderPrefix = "failed-order:"

    private static func badge(side: ApiPerpsPositionSide, leverage: Int?) -> String {
        let direction = lang(side == .long ? "Long" : "Short")
        guard let leverage, leverage > 0 else { return direction }
        return L10n.perpsLeverageDirection(leverage: leverage.formatted(.number.locale(.forNumberFormatters)), direction: direction)
    }

    func formatDate(
        relativeTo now: Date,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        switch dateValue {
        case .text(let text):
            return text
        case .timestamp(let time):
            let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            return ActivityDateFormatting.shortDateText(for: time, relativeTo: now, calendar: calendar, locale: locale)
                + " · " + time.formatted(format.hour().minute())
        }
    }
}

public final class PerpsTradeActivityCell: ActivitySummaryCell, ActivityDateDisplaying {
    private var activity: PerpsTradeActivity?

    public func configure(_ activity: PerpsTradeActivity, isStale: Bool, accessibilityPrefix: String) {
        self.activity = activity
        let amount = NSAttributedString(string: activity.amount.text, attributes: [.foregroundColor: activity.amount.tone.uiColor])
        let liquidated = activity.event == .liquidated
        let symbol = activity.isFailed ? "xmark" : activity.event == .opened || activity.event == .increased ? "arrow.up" : "arrow.down"
        let glyph = liquidated ? UIImage.airBundle("PerpsActivityLiquidated")
            : UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))!
        configure(title: activity.title, badge: activity.badge, date: activity.date, amount: amount, detail: activity.detail,
                  image: glyph, gradientColors: liquidated || activity.isFailed ? UIColor.air.redGradient : UIColor.air.blueGradient,
                  accessibilityIdentifier: accessibilityPrefix + activity.id, canSelect: true, isStale: isStale)
    }

    @discardableResult public func updateDate(relativeTo now: Date) -> Date? {
        guard let activity else { return nil }
        let date = activity.formatDate(relativeTo: now)
        if dateLabel.text != date {
            dateLabel.text = date
            accessibilityLabel = [activity.title, activity.badge, date].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return nil
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        activity = nil
    }
}
