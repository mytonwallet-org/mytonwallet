import UIKit
import UIComponents
import WalletContext
import WalletCore

final class TokenTradeSlippageSlider: UIControl {
    private let track = UIView()
    private let fill = UIView()
    private let thumb = UIView()
    private let ticks = TokenTradeSlippageScale.presets.map { _ in UIImageView(image: .airBundle("SlippageTick")) }
    private var position = TokenTradeSlippageScale.position(for: 5)
    private var capturedPreset: Int?
    private var touchOffset: CGFloat = 0
    private(set) var selectedValue = 5.0

    private var trackWidth: CGFloat { max(1, bounds.width - 38) }
    private var isRTL: Bool { effectiveUserInterfaceLayoutDirection == .rightToLeft }
    private var animates: Bool { AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled }

    override init(frame: CGRect) {
        super.init(frame: frame)
        tintColor = UIColor(hex: "#0088FF")
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = lang("Slippage")
        accessibilityIdentifier = "tokenTrade.slippage.slider"
        track.backgroundColor = .air.secondaryLabel.withAlphaComponent(0.2)
        track.layer.cornerRadius = 3
        fill.backgroundColor = tintColor
        fill.layer.cornerRadius = 3
        thumb.backgroundColor = .white
        thumb.layer.cornerRadius = 12
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOffset = CGSize(width: 0, height: 3)
        thumb.layer.shadowRadius = 6
        thumb.layer.shadowOpacity = 0.18
        [track, fill].forEach { addSubview($0) }
        ticks.forEach { addSubview($0) }
        addSubview(thumb)
        subviews.forEach { $0.isUserInteractionEnabled = false; $0.isAccessibilityElement = false }
        addGestureRecognizer(SlippageDragGestureRecognizer(target: self, action: #selector(dragged)))
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let x = centerX(at: position)
        let y: CGFloat = 26
        track.frame = CGRect(x: 0, y: y - 3, width: bounds.width, height: 6)
        fill.frame = CGRect(x: isRTL ? x : 0, y: y - 3, width: isRTL ? bounds.width - x : x, height: 6)
        thumb.bounds = CGRect(x: 0, y: 0, width: 38, height: 24)
        thumb.center = CGPoint(x: x, y: y)
        thumb.layer.shadowPath = UIBezierPath(roundedRect: thumb.bounds, cornerRadius: 12).cgPath
        for (index, tick) in ticks.enumerated() {
            tick.frame = CGRect(x: centerX(at: TokenTradeSlippageScale.positions[index + 1]) - 2, y: y + 8, width: 4, height: 4)
        }
    }

    func setValue(_ value: Double, animated: Bool) {
        selectedValue = value
        position = TokenTradeSlippageScale.position(for: value)
        updateAccessibilityValue()
        setNeedsLayout()
        if animated && animates {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.layoutIfNeeded()
            }
        } else {
            UIView.performWithoutAnimation { layoutIfNeeded() }
        }
    }

    @objc private func dragged(_ gesture: SlippageDragGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            touchOffset = thumb.frame.insetBy(dx: -8, dy: -10).contains(location) ? location.x - thumb.center.x : 0
            capturedPreset = TokenTradeSlippageScale.presets.firstIndex(of: selectedValue)
            Haptics.prepare(.selection)
            animateThumb(tracking: true)
            sendActions(for: .editingDidBegin)
            update(at: location.x - touchOffset)
        case .changed:
            update(at: location.x - touchOffset)
        case .ended:
            update(at: location.x - touchOffset)
            finishTracking()
        case .cancelled:
            finishTracking()
        default:
            break
        }
    }

    override func accessibilityIncrement() { adjustValue(increasing: true) }
    override func accessibilityDecrement() { adjustValue(increasing: false) }

    private func centerX(at position: Double) -> CGFloat {
        19 + CGFloat(isRTL ? 1 - position : position) * trackWidth
    }

    private func update(at x: CGFloat) {
        let rawPosition = min(1, max(0, Double((x - 19) / trackWidth)))
        let logicalPosition = isRTL ? 1 - rawPosition : rawPosition
        let selection = TokenTradeSlippageScale.selection(at: logicalPosition, trackWidth: Double(trackWidth), capturedPreset: capturedPreset)
        if let preset = selection.presetIndex, preset != capturedPreset {
            Haptics.play(.selection)
            Haptics.prepare(.selection)
        }
        capturedPreset = selection.presetIndex
        // Keep the finger position independent of the rounded value to avoid feedback jitter.
        position = selection.presetIndex == nil ? logicalPosition : TokenTradeSlippageScale.position(for: selection.value)
        let changed = selectedValue != selection.value
        selectedValue = selection.value
        updateAccessibilityValue()
        setNeedsLayout()
        layoutIfNeeded()
        if changed { sendActions(for: .valueChanged) }
    }

    private func finishTracking() {
        capturedPreset = nil
        animateThumb(tracking: false)
        setValue(selectedValue, animated: true)
        sendActions(for: .editingDidEnd)
    }

    private func animateThumb(tracking: Bool) {
        let changes = { self.thumb.transform = tracking ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity }
        if animates {
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    private func adjustValue(increasing: Bool) {
        let step = selectedValue > 5 || (increasing && selectedValue == 5) ? 1.0 : 0.1
        let value = (selectedValue + (increasing ? step : -step)) * 10
        setValue(min(50, max(0.1, value.rounded() / 10)), animated: true)
        Haptics.play(.selection)
        sendActions(for: .valueChanged)
    }

    private func updateAccessibilityValue() {
        accessibilityValue = formatBigIntText(BigInt(Int((selectedValue * 10).rounded())), tokenDecimals: SLIPPAGE_DECIMALS) + "%"
    }
}

// Claim the touch immediately, before an ancestor scroll view or sheet can start panning.
private final class SlippageDragGestureRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible {
            state = .began
        } else {
            touches.forEach { ignore($0, for: event) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .ended }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        preventingGestureRecognizer is UIPanGestureRecognizer ? false : super.canBePrevented(by: preventingGestureRecognizer)
    }
}
