import UIKit

/// A zoomable stage for one piece of media in a full-screen viewer, as the NFT viewer's: the media fills the stage at
/// its proportions, pinches from 1x to 4x, and a double tap zooms in 3x where it lands or back out. Media smaller than
/// the stage stays in its middle.
@MainActor
public final class MediaZoomView: UIScrollView, UIScrollViewDelegate {
    public enum Fitting {
        /// A square as wide as the stage, as an NFT
        case squareOfWidth
        /// The largest frame of the media's proportions, height over width, that the stage holds
        case aspectFit(CGFloat)
    }

    private static let doubleTapZoomScale: CGFloat = 3

    /// Holds the media; it is what zooms
    public let contentContainerView = UIView()
    public var fitting: Fitting = .squareOfWidth {
        didSet { setNeedsLayout() }
    }
    public var onZoom: (() -> Void)?
    public var onScroll: (() -> Void)?

    private var contentWidthConstraint: NSLayoutConstraint!
    private var contentHeightConstraint: NSLayoutConstraint!

    public override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        bouncesZoom = true
        bounces = false
        alwaysBounceVertical = false
        contentInsetAdjustmentBehavior = .never
        clipsToBounds = false
        if #available(iOS 26.0, *) {
            topEdgeEffect.isHidden = true
        }
        delegate = self
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainerView)
        contentWidthConstraint = contentContainerView.widthAnchor.constraint(equalToConstant: frame.width)
        contentHeightConstraint = contentContainerView.heightAnchor.constraint(equalToConstant: frame.width)
        NSLayoutConstraint.activate([
            contentContainerView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            contentWidthConstraint,
            contentHeightConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var isAtMinimumZoom: Bool {
        zoomScale <= minimumZoomScale + 0.001
    }

    /// The media's frame at 1x, centred in the stage
    public var fittedSize: CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        switch fitting {
        case .squareOfWidth:
            return CGSize(width: bounds.width, height: bounds.width)
        case .aspectFit(let ratio):
            let width = min(bounds.width, bounds.height / max(ratio, 0.01))
            return CGSize(width: width, height: width * ratio)
        }
    }

    /// Sizes the media for the stage at 1x. Call as the stage's size changes.
    public func updateContentSize() {
        let size = fittedSize
        guard size.width > 0, contentWidthConstraint.constant != size.width || contentHeightConstraint.constant != size.height else { return }
        contentWidthConstraint.constant = size.width
        contentHeightConstraint.constant = size.height
    }

    /// Keeps media smaller than the stage in its middle
    public func centerContent() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    /// Zooms back out if zoomed in, or in 3x around `point` in the media's coordinates
    public func toggleZoom(at point: CGPoint) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let width = bounds.width / Self.doubleTapZoomScale
            let height = bounds.height / Self.doubleTapZoomScale
            zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
        }
    }

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentContainerView
    }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        onZoom?()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?()
    }
}
