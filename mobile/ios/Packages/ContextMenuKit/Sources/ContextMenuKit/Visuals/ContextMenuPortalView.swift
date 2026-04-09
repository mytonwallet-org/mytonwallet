import UIKit

@MainActor
final class ContextMenuPortalView: UIView {
    private let portalContentView: UIView
    private let portalMaskLayer = CAShapeLayer()

    init?(sourceView: UIView, matchPosition: Bool = true) {
        guard let portalContentView = ContextMenuPortalView.makePortalContentView(matchPosition: matchPosition) else {
            return nil
        }

        self.portalContentView = portalContentView

        super.init(frame: .zero)

        self.isUserInteractionEnabled = false
        self.portalContentView.isUserInteractionEnabled = false
        self.addSubview(self.portalContentView)
        self.updateSourceView(sourceView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.portalContentView.frame = self.bounds
    }

    func updateSourceView(_ sourceView: UIView?) {
        ContextMenuPrivatePortalRuntime.setProperty(
            sourceView,
            selector: ContextMenuPrivatePortalRuntime.setSourceViewSelector,
            on: self.portalContentView
        )
    }

    func updateMask(_ mask: ContextMenuSourcePortalMask?, rect maskRect: CGRect?) {
        guard let mask, let maskRect else {
            self.layer.mask = nil
            return
        }

        self.portalMaskLayer.frame = self.bounds
        self.portalMaskLayer.path = ContextMenuPortalMaskShape.path(for: mask, in: maskRect)
        self.portalMaskLayer.fillColor = UIColor.white.cgColor
        self.layer.mask = self.portalMaskLayer
    }

    private static func makePortalContentView(matchPosition: Bool) -> UIView? {
        guard let portalViewClass = ContextMenuPrivatePortalRuntime.portalViewClass else {
            return nil
        }

        let portalView = portalViewClass.init(frame: .zero)
        ContextMenuPrivatePortalRuntime.setProperty(
            matchPosition,
            selector: ContextMenuPrivatePortalRuntime.setMatchesPositionSelector,
            on: portalView
        )
        ContextMenuPrivatePortalRuntime.setProperty(
            matchPosition,
            selector: ContextMenuPrivatePortalRuntime.setMatchesTransformSelector,
            on: portalView
        )
        ContextMenuPrivatePortalRuntime.setProperty(
            false,
            selector: ContextMenuPrivatePortalRuntime.setMatchesAlphaSelector,
            on: portalView
        )
        ContextMenuPrivatePortalRuntime.setProperty(
            false,
            selector: ContextMenuPrivatePortalRuntime.setAllowsHitTestingSelector,
            on: portalView
        )
        ContextMenuPrivatePortalRuntime.setProperty(
            false,
            selector: ContextMenuPrivatePortalRuntime.setForwardsClientHitTestingToSourceViewSelector,
            on: portalView
        )
        return portalView
    }
}
