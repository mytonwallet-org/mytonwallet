import Combine
import UIKit
import WalletContext

/// The frame of an amount-entry trade screen, shared by Buy/Sell and futures orders: an amount card above
/// the payment row, and input controls over the keypad. Subclasses add the card's footer.
open class NativeTradeEntryView: UIView {
    public let scrollView = UIScrollView()
    public let amountCard = UIView()
    public let amountField = TradeTextField()
    public let conversion = TradeConversionControl(frame: .zero)
    public let method: TradePaymentControl
    public let keypad: TradeKeypad
    private let editor = TradeEditor()
    private let controlsBackground = UIView()
    private let controls: UIView
    private var environmentSubscription: AnyCancellable?

    public init(method: TradePaymentControl, controls: UIView, keypadAccessibilityPrefix: String) {
        self.method = method
        self.controls = controls
        keypad = TradeKeypad(editor: editor, accessibilityPrefix: keypadAccessibilityPrefix)
        super.init(frame: .zero)
        backgroundColor = .air.headerBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.keyboardDismissMode = .none
        addSubview(scrollView)
        addSubview(controlsBackground)
        scrollView.addSubview(amountCard)
        scrollView.addSubview(method)
        amountCard.addSubview(conversion)
        amountCard.addSubview(amountField)
        controlsBackground.addSubview(controls)
        controlsBackground.addSubview(keypad)
        for background in [amountCard, controlsBackground] {
            background.backgroundColor = .air.pickerBackground
            background.layer.cornerRadius = 32
            background.layer.cornerCurve = .continuous
        }
        controlsBackground.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        editor.field = amountField
        amountField.caretColor = AirTintColor
        let environment = CardBackgroundAnimationEnvironment.shared
        environmentSubscription = Publishers.CombineLatest4(environment.$applicationActive, environment.$animationsEnabled,
            environment.$lowPowerMode, environment.$reduceMotion).sink { [weak self] _ in
                // Read policy after @Published completes its write.
                DispatchQueue.main.async { [weak self] in self?.refreshMotionPolicy() }
            }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func install(in parent: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor), trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor), bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    open func refreshMotionPolicy() {
        let active = window != nil && CardBackgroundAnimationEnvironment.shared.applicationActive
        amountField.configureAnimation(active: active, animated: active && TradeMotion.enabled)
        // Only the pending-quote masks animate; their state is independent of layout.
        conversion.refreshMotionPolicy()
        method.refreshMotionPolicy()
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshMotionPolicy()
    }

    /// Places the frame for `layout` and returns the amount field's frame in the card.
    @discardableResult
    public func layoutEntry(_ layout: NativeTradeLayout, amountTrailingInset: CGFloat = 0) -> CGRect {
        let width = bounds.width
        TradeMotion.place(scrollView, in: layout.scroll)
        TradeMotion.place(amountCard, in: layout.card)
        TradeMotion.place(method, in: layout.method)
        scrollView.contentSize = CGSize(width: width, height: layout.contentHeight)
        scrollView.alwaysBounceVertical = layout.contentHeight > layout.scroll.height
        TradeMotion.place(controlsBackground, in: layout.controls)
        TradeMotion.place(controls, in: CGRect(x: 24, y: 24, width: max(0, width - 48), height: 52))
        TradeMotion.place(keypad, in: CGRect(x: 0, y: 88, width: width, height: layout.keypadHeight))
        amountField.maximumHeight = layout.maximumAmountHeight
        let amountWidth = max(1, width - 28 - amountTrailingInset)
        let fieldHeight = amountField.fittingHeight(forWidth: amountWidth)
        let top = layout.amountTop + max(0, (layout.maximumAmountHeight - fieldHeight) / 2)
        let amountFrame = CGRect(x: 24, y: top + 26, width: amountWidth, height: fieldHeight)
        placeInCard(conversion, CGRect(x: 24, y: top, width: min(max(0, width - 48), conversion.intrinsicContentSize.width), height: 26))
        placeInCard(amountField, amountFrame)
        return amountFrame
    }

    /// Places a card subview, mirrored in right-to-left layouts.
    public func placeInCard(_ view: UIView, _ frame: CGRect) {
        var frame = frame
        if effectiveUserInterfaceLayoutDirection == .rightToLeft { frame.origin.x = bounds.width - frame.maxX }
        TradeMotion.place(view, in: frame)
    }
}
