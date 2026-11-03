import Dependencies
import SwiftNavigation
import UIComponents
import UIKit
import WalletContext
import WalletCore

final class PerpsPositionsSummaryCell: UICollectionViewCell {
    @Dependency(\.sensitiveData) private var sensitiveData
    private let titleLabel = UILabel()
    let balance = MtwCardBalanceLabelView()
    let change = MtwCardChangeView()
    private lazy var balanceShine = TradeShineView(content: balance)
    private lazy var changeShine = TradeShineView(content: change)
    private var data: PerpsPositionsDisplayData?
    private var observation: ObserveToken?
    private var showsChange = false
    private var isConfigured = false

    static func showsChange(for data: PerpsPositionsDisplayData) -> Bool {
        data.status == .ready && data.totalValue.optionalAmount.map { $0 != 0 } == true
    }

    static func height(for data: PerpsPositionsDisplayData) -> CGFloat {
        showsChange(for: data) ? 172 : 132
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.applyTextStyle(.subheadlineStrong)
        titleLabel.textColor = .air.secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.text = lang("Open Positions")
        titleLabel.accessibilityTraits.insert(.header)
        balance.accessibilityIdentifier = "perps.home.total"
        change.accessibilityIdentifier = "perps.home.change"
        for view in [titleLabel, balanceShine, changeShine] { contentView.addSubview(view) }
        balance.onTap = { [weak self] in self?.togglePrivacy() }
        observation = observe { [weak self] in
            guard let self else { return }
            render(isHidden: sensitiveData.isHidden)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ data: PerpsPositionsDisplayData) {
        self.data = data
        render(isHidden: sensitiveData.isHidden)
    }

    private func render(isHidden: Bool) {
        guard let data else { return }
        let animated = isConfigured && window != nil && AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled
        let nextShowsChange = Self.showsChange(for: data)
        let visibilityChanged = showsChange != nextShowsChange
        showsChange = nextShowsChange
        titleLabel.applyTextStyle(.subheadlineStrong)
        titleLabel.text = lang("Open Positions")
        balance.configure(balance: data.totalValue.optionalAmount == nil ? nil : data.totalValue,
                          style: .homeNavigationBarCollapsed, nft: nil, usesCardGradient: false,
                          isHidden: isHidden, isScrolling: false, animates: animated)
        let color: UIColor = switch data.profitLoss.tone {
        case .negative: .air.negativeAmount
        case .positive: UIColor(hex: "34C759")
        case .neutral: .air.secondaryLabel
        }
        // Retain outgoing content until its fade completes when the balance becomes zero.
        if nextShowsChange {
            change.configure(text: data.profitLoss.text, color: color,
                             backgroundOpacity: data.profitLoss.tone == .negative ? 0.12 : 0.10,
                             height: 28, isHidden: isHidden, animates: animated)
        }
        change.accessibilityElementsHidden = !nextShowsChange
        change.isUserInteractionEnabled = nextShowsChange
        if !nextShowsChange { change.isAccessibilityElement = false }
        if visibilityChanged && animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.changeShine.alpha = nextShowsChange ? 1 : 0
                self.changeShine.transform = nextShowsChange ? .identity : CGAffineTransform(translationX: 0, y: -6)
            }
        } else {
            changeShine.alpha = nextShowsChange ? 1 : 0
            changeShine.transform = nextShowsChange ? .identity : CGAffineTransform(translationX: 0, y: -6)
        }
        isConfigured = true
        balanceShine.setActive(data.isStale && !isHidden, animated: animated)
        changeShine.setActive(data.isStale && !isHidden, animated: animated)
        change.setPrivacyAnimationActive(window != nil && showsChange)
        setNeedsLayout()
    }

    private func togglePrivacy() {
        let point = balance.lastTapLocation ?? CGPoint(x: balance.bounds.midX, y: balance.bounds.midY)
        balance.preparePrivacyTransition(at: point)
        change.preparePrivacyTransition(at: change.convert(point, from: balance))
        AppActions.setSensitiveDataIsHidden(!sensitiveData.isHidden)
    }

    func setPrivacyAnimationActive(_ active: Bool) {
        balance.setPrivacyAnimationActive(active)
        change.setPrivacyAnimationActive(active && showsChange)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setPrivacyAnimationActive(window != nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(0, contentView.bounds.width - 32)
        titleLabel.frame = CGRect(x: 16, y: 22, width: width, height: 22)
        let height = MtwCardBalanceView.Style.homeNavigationBarCollapsed.integerFont.lineHeight
        balanceShine.frame = CGRect(x: 16, y: 83 - height / 2, width: width, height: height)
        // Use bounds/center so relayout does not interrupt the appearance transform.
        changeShine.bounds = CGRect(x: 0, y: 0, width: width, height: 28)
        changeShine.center = CGPoint(x: contentView.bounds.midX, y: 130)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size.height = data.map(Self.height) ?? 132
        return attributes
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        data = nil
        isConfigured = false
        balance.prepareForReuse()
        change.prepareForReuse()
        balanceShine.setActive(false, animated: false)
        changeShine.setActive(false, animated: false)
    }
}
