import SwiftUI
import UIKit

/// The front card of a stack floating over content: Liquid Glass, or a thin material before iOS 26
struct PromotionFloatingGlass: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        }
    }
}

/// A card behind the floating front card, frosting what is under it. Only its part below the front card shows, and
/// a sliver under the front card's corners, so the front glass stays clear.
struct PromotionFrostedBackplate: UIViewRepresentable {
    let cornerRadius: CGFloat
    /// 1 for the card right behind the front one
    let depth: Int

    /// How far each card behind shows below the one in front of it, as `HomePromotionStack` offsets it
    private static let peek: CGFloat = 8
    /// How much shows above the bottom of the card in front, to fill in its rounded corners. They rise less than a
    /// point over this card's sides, which `HomePromotionStack` narrows by 24 pt each.
    private static let cornerFill: CGFloat = 2

    func makeUIView(context: Context) -> FrostedBackplateView {
        FrostedBackplateView(cornerRadius: cornerRadius)
    }

    func updateUIView(_ view: FrostedBackplateView, context: Context) {
        view.visibleHeight = Self.peek * CGFloat(depth) + Self.cornerFill
    }
}

/// A `UIVisualEffectView` cut to its bottom part by clipping, never by a mask or alpha: those, on it or on any of
/// its ancestors, turn the blur into plain translucency
final class FrostedBackplateView: UIView {
    private let clipView = UIView()
    private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let borderView = UIView()
    private static let borderColor = UIColor {
        $0.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.16) : .black.withAlphaComponent(0.1)
    }

    var visibleHeight: CGFloat = .greatestFiniteMagnitude {
        didSet {
            if visibleHeight != oldValue { setNeedsLayout() }
        }
    }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipView.clipsToBounds = true
        addSubview(clipView)
        for view in [effectView, borderView] as [UIView] {
            view.layer.cornerRadius = cornerRadius
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
            clipView.addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = min(visibleHeight, bounds.height)
        clipView.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        let card = CGRect(x: 0, y: height - bounds.height, width: bounds.width, height: bounds.height)
        effectView.frame = card
        borderView.frame = card
        updateBorder()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorder()
    }

    private func updateBorder() {
        borderView.layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        borderView.layer.borderColor = Self.borderColor.resolvedColor(with: traitCollection).cgColor
    }
}
