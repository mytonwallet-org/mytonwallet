import SwiftUI
import WalletContext

public extension View {
    func foregroundForTintedBackground() -> some View {
        modifier(TintedForegroundModifier())
    }
}

private struct TintedForegroundModifier: ViewModifier {
    @State private var color = Color.white

    func body(content: Content) -> some View {
        content
            .foregroundStyle(color)
            .background {
                TintObserver { color = Color($0) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

struct TintObserver: UIViewRepresentable {
    var onChange: (UIColor) -> Void

    func makeUIView(context: Context) -> TintObserverView {
        TintObserverView()
    }

    func updateUIView(_ uiView: TintObserverView, context: Context) {
        uiView.onChange = onChange
        uiView.updateColor()
    }
}

final class TintObserverView: UIView {
    var onChange: ((UIColor) -> Void)?
    private var lastColor: UIColor?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateColor()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColor()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateColor()
        }
    }

    func updateColor() {
        // Resolve inherited tint in UIKit; SwiftUI drops that dependency inside a dynamic UIColor.
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            let color = tintColor.foregroundForTintedBackground.resolvedColor(with: traitCollection)
            guard color != lastColor else { return }
            lastColor = color
            onChange?(color)
        }
    }
}
