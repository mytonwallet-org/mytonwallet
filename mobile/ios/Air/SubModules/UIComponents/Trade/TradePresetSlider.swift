import UIKit
import WalletContext
import WalletCore

open class TradePresetSlider: UIControl {
    private let track = UIView()
    private let fill = UIView()
    private let thumb = UIView()
    private let scale: TradeSliderScale
    private let formatValue: (Double) -> String
    private let ticks: [UIImageView]
    private var position: Double
    private var capturedPreset: Int?
    private var touchOffset: CGFloat = 0
    public private(set) var selectedValue: Double

    private var trackWidth: CGFloat { max(1, bounds.width - 38) }
    private var isRTL: Bool { effectiveUserInterfaceLayoutDirection == .rightToLeft }
    private var animates: Bool { AppStorageHelper.animations && !UIAccessibility.isReduceMotionEnabled }

    public init(scale: TradeSliderScale, value: Double, formatValue: @escaping (Double) -> String) {
        self.scale = scale
        self.formatValue = formatValue
        selectedValue = min(scale.maximum, max(scale.minimum, value))
        position = scale.position(for: value)
        ticks = scale.presets.map { _ in UIImageView(image: .airBundle("SlippageTick")) }
        super.init(frame: .zero)
        tintColor = UIColor(hex: "#0088FF")
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
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
        addGestureRecognizer(TradeSliderDragGestureRecognizer(target: self, action: #selector(dragged)))
        updateAccessibilityValue()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let x = centerX(at: position)
        let y: CGFloat = 26
        track.frame = CGRect(x: 0, y: y - 3, width: bounds.width, height: 6)
        fill.frame = CGRect(x: isRTL ? x : 0, y: y - 3, width: isRTL ? bounds.width - x : x, height: 6)
        thumb.bounds = CGRect(x: 0, y: 0, width: 38, height: 24)
        thumb.center = CGPoint(x: x, y: y)
        thumb.layer.shadowPath = UIBezierPath(roundedRect: thumb.bounds, cornerRadius: 12).cgPath
        for (index, tick) in ticks.enumerated() {
            tick.frame = CGRect(x: centerX(at: scale.positions[index + 1]) - 2, y: y + 8, width: 4, height: 4)
        }
    }

    public func setValue(_ value: Double, animated: Bool) {
        selectedValue = min(scale.maximum, max(scale.minimum, value))
        position = scale.position(for: value)
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

    @objc private func dragged(_ gesture: TradeSliderDragGestureRecognizer) {
        guard isEnabled else { return }
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            touchOffset = thumb.frame.insetBy(dx: -8, dy: -10).contains(location) ? location.x - thumb.center.x : 0
            capturedPreset = scale.presets.firstIndex(of: selectedValue)
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

    public override func accessibilityIncrement() { adjustValue(increasing: true) }
    public override func accessibilityDecrement() { adjustValue(increasing: false) }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        fill.backgroundColor = tintColor
    }

    private func centerX(at position: Double) -> CGFloat {
        19 + CGFloat(isRTL ? 1 - position : position) * trackWidth
    }

    private func update(at x: CGFloat) {
        let rawPosition = min(1, max(0, Double((x - 19) / trackWidth)))
        let logicalPosition = isRTL ? 1 - rawPosition : rawPosition
        let selection = scale.selection(at: logicalPosition, trackWidth: Double(trackWidth), capturedPreset: capturedPreset)
        if let preset = selection.presetIndex, preset != capturedPreset {
            Haptics.play(.selection)
            Haptics.prepare(.selection)
        }
        capturedPreset = selection.presetIndex
        // Keep the finger position independent of the rounded value to avoid feedback jitter.
        position = selection.presetIndex == nil ? logicalPosition : scale.position(for: selection.value)
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
        setValue(scale.adjustedValue(selectedValue, increasing: increasing), animated: true)
        Haptics.play(.selection)
        sendActions(for: .valueChanged)
    }

    private func updateAccessibilityValue() {
        accessibilityValue = formatValue(selectedValue)
    }
}

// Claim the touch immediately, before an ancestor scroll view or sheet can start panning.
private final class TradeSliderDragGestureRecognizer: UIGestureRecognizer {
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible {
            state = .began
        } else {
            touches.forEach { ignore($0, for: event) }
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .ended }
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }

    public override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        preventingGestureRecognizer is UIPanGestureRecognizer ? false : super.canBePrevented(by: preventingGestureRecognizer)
    }
}
