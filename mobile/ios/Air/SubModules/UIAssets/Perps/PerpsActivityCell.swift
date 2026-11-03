import UIComponents
import UIKit
import WalletContext

final class PerpsActivityCell: ActivitySummaryCell {
    override init(frame: CGRect) { super.init(frame: frame) }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ activity: PerpsHomeActivity) {
        let amount = NSMutableAttributedString()
        if let previous = activity.previousAmount {
            amount.append(NSAttributedString(string: previous, attributes: [.foregroundColor: UIColor.air.secondaryLabel]))
            amount.append(NSAttributedString(string: " → ", attributes: [.foregroundColor: UIColor.label]))
        }
        amount.append(NSAttributedString(string: activity.amount.text, attributes: [.foregroundColor: activity.amount.tone.uiColor]))
        let liquidated = activity.kind == .liquidated
        let symbol: String = switch activity.kind {
        case .transfer: "arrow.left.arrow.right"
        case .opened, .increased, .sent: "arrow.up"
        default: "arrow.down"
        }
        let glyph = liquidated ? UIImage.airBundle("PerpsActivityLiquidated")
            : UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))!
        configure(title: activity.title, badge: activity.badge, date: activity.date, amount: amount,
                  detail: activity.amountDetail,
                  image: glyph, gradientColors: liquidated ? UIColor.air.redGradient : UIColor.air.blueGradient,
                  accessibilityIdentifier: "perps.home.activity." + activity.id, canSelect: activity.canSelect, isStale: activity.isStale)
    }
}
