import UIKit

@MainActor
public final class BlurReplaceView: UIView {
    public private(set) var contentView: UIView?
    public var maximumBlurRadius: CGFloat = 12
    public var animationDuration: TimeInterval = 0.35

    private var currentWrapper: WBlurredContentView?
    private var transitionGeneration = 0
    private var pendingCompletion: ((Bool) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public convenience init(contentView: UIView) {
        self.init(frame: .zero)
        replaceContent(with: contentView, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        contentView?.intrinsicContentSize ?? super.intrinsicContentSize
    }

    public override func layoutSubviews() {
        // Replacement motion belongs to the wrappers' opacity and blur. Incoming
        // content must not inherit a parent's geometry animation from a zero frame.
        UIView.performWithoutAnimation {
            super.layoutSubviews()
            for wrapper in wrappers { wrapper.layoutIfNeeded() }
        }
    }

    public func replaceContent(
        with contentView: UIView,
        animated: Bool = true,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard self.contentView !== contentView else {
            completion?(true)
            return
        }

        transitionGeneration += 1
        let generation = transitionGeneration

        cancelCurrentTransition()
        let previousWrappers = wrappers
        self.contentView = contentView
        invalidateIntrinsicContentSize()

        let incomingWrapper = makeWrapper(for: contentView)
        addSubview(incomingWrapper)
        pinToBounds(incomingWrapper)
        UIView.performWithoutAnimation { layoutIfNeeded() }

        guard animated, !previousWrappers.isEmpty else {
            previousWrappers.forEach { $0.removeFromSuperview() }
            incomingWrapper.alpha = 1
            incomingWrapper.blurRadius = 0
            incomingWrapper.isUserInteractionEnabled = true
            self.currentWrapper = incomingWrapper
            completion?(true)
            return
        }

        for wrapper in previousWrappers {
            wrapper.isUserInteractionEnabled = false
            wrapper.accessibilityElementsHidden = true
        }
        incomingWrapper.alpha = 0
        incomingWrapper.blurRadius = maximumBlurRadius
        incomingWrapper.isUserInteractionEnabled = false
        incomingWrapper.accessibilityElementsHidden = false
        self.currentWrapper = incomingWrapper
        pendingCompletion = completion

        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut]
        ) {
            for wrapper in previousWrappers {
                wrapper.alpha = 0
                wrapper.blurRadius = self.maximumBlurRadius
            }
            incomingWrapper.alpha = 1
            incomingWrapper.blurRadius = 0
        } completion: { [weak self, weak incomingWrapper] finished in
            guard let self, self.transitionGeneration == generation else { return }
            previousWrappers.forEach { $0.removeFromSuperview() }
            incomingWrapper?.isUserInteractionEnabled = true
            let completion = self.pendingCompletion
            self.pendingCompletion = nil
            completion?(finished)
        }
    }

    private func makeWrapper(for contentView: UIView) -> WBlurredContentView {
        let wrapper = WBlurredContentView()
        wrapper.accessibilityElementsHidden = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    private func pinToBounds(_ view: UIView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func cancelCurrentTransition() {
        pendingCompletion?(false)
        pendingCompletion = nil

        for wrapper in wrappers {
            wrapper.removeBlurRadiusAnimation()
            let visibleAlpha = CGFloat(wrapper.layer.presentation()?.opacity ?? Float(wrapper.alpha))
            wrapper.layer.removeAllAnimations()
            wrapper.alpha = visibleAlpha
        }
    }

    private var wrappers: [WBlurredContentView] {
        subviews.compactMap { $0 as? WBlurredContentView }
    }
}
