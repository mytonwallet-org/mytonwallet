import UIKit

@MainActor
final class ContextMenuPortalView: UIView {
    private let portalContentView: UIView
    private let portalMaskLayer = CAShapeLayer()
    private let flipsPortalContent: Bool

    init?(
        sourceView: UIView,
        sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection,
        appliesRightToLeftTransformCorrection: Bool,
        matchPosition: Bool = true
    ) {
        let usesRightToLeftLayout = sourceUserInterfaceLayoutDirection == .rightToLeft
        let flipsPortalContent = usesRightToLeftLayout && appliesRightToLeftTransformCorrection
        let matchesPosition = usesRightToLeftLayout ? false : matchPosition
        guard let portalContentView = ContextMenuPortalView.makePortalContentView(
            matchesPosition: matchesPosition,
            matchesTransform: matchPosition
        ) else {
            return nil
        }
        self.portalContentView = portalContentView
        self.flipsPortalContent = flipsPortalContent

        super.init(frame: .zero)

        let semanticContentAttribute = sourceUserInterfaceLayoutDirection.contextMenuSemanticContentAttribute
        self.semanticContentAttribute = semanticContentAttribute
        self.portalContentView.semanticContentAttribute = semanticContentAttribute
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

        self.portalContentView.layer.transform = CATransform3DIdentity
        self.portalContentView.frame = self.bounds
        if self.flipsPortalContent {
            self.portalContentView.layer.transform = CATransform3DMakeScale(-1.0, 1.0, 1.0)
        }
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

    private static func makePortalContentView(matchesPosition: Bool, matchesTransform: Bool) -> UIView? {
        guard let portalViewClass = ContextMenuPrivatePortalRuntime.portalViewClass else {
            return nil
        }

        let portalView = portalViewClass.init(frame: .zero)
        ContextMenuPrivatePortalRuntime.setProperty(
            matchesPosition,
            selector: ContextMenuPrivatePortalRuntime.setMatchesPositionSelector,
            on: portalView
        )
        ContextMenuPrivatePortalRuntime.setProperty(
            matchesTransform,
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
