import UIKit
import WalletContext

/// One retained control tree for Buy/Sell and position orders.
public final class NativeTradeInputControls: UIView {
    public let continueButton: NativeTradeContinueButton
    private let fractions = UIView()
    private var fractionButtons: [TradePressButton] = []
    private lazy var continuePresence = TradePresenceView(continueButton)
    private lazy var fractionsPresence = TradePresenceView(fractions)

    public init(percentages: [Int], showsPositiveSign: Bool = false, accessibilityPrefix: String,
                onFraction: @escaping (Int) -> Void, onContinue: @escaping () -> Void) {
        continueButton = NativeTradeContinueButton(action: onContinue)
        super.init(frame: .zero)
        continueButton.button.accessibilityIdentifier = accessibilityPrefix + ".review"
        addSubview(continuePresence)
        addSubview(fractionsPresence)
        for percentage in percentages {
            let button = TradePressButton(frame: .zero)
            let label = UILabel()
            label.text = (showsPositiveSign && percentage > 0 ? "+" : "")
                + percentage.formatted(.percent.scale(1).locale(.forNumberFormatters))
            label.font = WTypography.uiFont(.bodyEmphasized)
            label.textColor = .label
            label.textAlignment = .center
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            button.content.addSubview(label)
            button.content.backgroundColor = .air.headerBackground
            button.content.layer.cornerRadius = 26
            button.content.layer.cornerCurve = .continuous
            button.accessibilityLabel = label.text
            button.accessibilityIdentifier = accessibilityPrefix + ".fraction.\(percentage)"
            button.addAction(UIAction { _ in onFraction(percentage) }, for: .touchUpInside)
            fractions.addSubview(button)
            fractionButtons.append(button)
        }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(configuration: DraftButtonConfiguration, tintColor: UIColor, showsContinue: Bool,
                       fractionsEnabled: Bool, animated: Bool,
                       onRender: ((DraftButtonConfiguration, WButton, String?) -> Void)? = nil) {
        continueButton.update(configuration: configuration, tintColor: tintColor, onRender: onRender, animated: animated)
        fractionButtons.forEach { $0.isEnabled = fractionsEnabled }
        continuePresence.setContentVisible(showsContinue, animated: animated)
        fractionsPresence.setContentVisible(!showsContinue, animated: animated)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        TradeMotion.place(continuePresence, in: bounds)
        TradeMotion.place(fractionsPresence, in: bounds)
        let count = fractionButtons.count
        guard count > 0 else { return }
        let width = max(0, (bounds.width - CGFloat(count - 1) * 10) / CGFloat(count))
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, button) in fractionButtons.enumerated() {
            let x = CGFloat(rtl ? count - 1 - index : index) * (width + 10)
            TradeMotion.place(button, in: CGRect(x: x, y: 0, width: width, height: bounds.height))
        }
    }
}
