import UIKit
import WalletContext
import UIComponents

protocol NftDetailsFullScreenOverlayContent: UIView {
    var centerYConstraint: NSLayoutConstraint? { get set }
    var centerXConstraint: NSLayoutConstraint? { get set }
}

extension NftDetailsFullScreenOverlayContent {
    private func removeCenterConstraints() {
        var oldConstraints: [NSLayoutConstraint] = []
        if let oldCenterXConstraint = centerXConstraint {
            oldConstraints.append(oldCenterXConstraint)
        }
        if let oldCenterYConstraint = centerYConstraint {
            oldConstraints.append(oldCenterYConstraint)
        }
        NSLayoutConstraint.deactivate(oldConstraints)
        
        self.centerXConstraint = nil
        self.centerYConstraint = nil
    }
    
    func addToParent(_ parent: UIView, bindToTop: Bool, yConstant: CGFloat) {
        removeCenterConstraints()
        
        parent.addSubview(self)
        
        centerXConstraint = centerXAnchor.constraint(equalTo: parent.centerXAnchor, constant: 0)
        if bindToTop {
            centerYConstraint = centerYAnchor.constraint(equalTo: parent.topAnchor, constant: yConstant )
        } else {
            centerYConstraint = centerYAnchor.constraint(equalTo: parent.centerYAnchor, constant: yConstant )
        }
        NSLayoutConstraint.activate([centerXConstraint!, centerYConstraint!])
    }
}


class NftDetailsFullScreenOverlay: UIView {
    
    private let doubleTapZoomScale: CGFloat = 3.0

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 4.0
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.bouncesZoom = true
        sv.bounces = true
        sv.alwaysBounceVertical = true
        sv.contentInsetAdjustmentBehavior = .never
        return sv
    }()
    
    private let contentContainerView = UIView()
    private var contentContainerWidthConstraint: NSLayoutConstraint!
    private var contentContainerHeightConstraint: NSLayoutConstraint!
    private weak var content: NftDetailsFullScreenOverlayContent?
    private var dismissPanGesture: UIPanGestureRecognizer?
    private var onDismiss: ((DismissWay) -> Void)?

    private enum State {
        case idle, presenting, normal, dismissing
    }
    
    private var state = State.idle
    

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateContainerSize()
        centerContent()
    }

    private func updateContainerSize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
                                                
        // Content is always square (matches NFT image aspect ratio expectations)
        let fittedSize = bounds.width
        contentContainerWidthConstraint.constant = fittedSize
        contentContainerHeightConstraint.constant = fittedSize
        scrollView.contentSize = CGSize(width: fittedSize, height: fittedSize)
    }
    
    private func updateBackground() {
        if scrollView.zoomScale == 1.0 {
            let start = CGFloat(0)
            let end = CGFloat(100)
            let offset = max(start, min(end, abs(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)))
            backgroundColor = UIColor.black.withAlphaComponent(1 - (offset - start) / (end - start))
        } else {
            backgroundColor = UIColor.black
        }
    }

    private func centerContent() {
        let scrollSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize

        let hInset = max((scrollSize.width - contentSize.width) / 2, 0)
        let vInset = max((scrollSize.height - contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: vInset, left: hInset, bottom: vInset, right: hInset)
    }

    private func setup() {
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentContainerView)

        contentContainerWidthConstraint = contentContainerView.widthAnchor.constraint(equalToConstant: bounds.width)
        contentContainerHeightConstraint = contentContainerView.heightAnchor.constraint(equalToConstant: bounds.width)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentContainerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentContainerWidthConstraint,
            contentContainerHeightConstraint,
        ])

        // Double-tap on content toggles zoom: resets to 1× if zoomed, zooms in if at 1
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single tap on background dismisses when at base zoom.
        // Single tap must wait for double-tap to fail so they don't conflict.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        tap.require(toFail: doubleTap)

        
        let dismissPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPanGesture.delegate = self
        dismissPanGesture.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(dismissPanGesture)
        self.dismissPanGesture = dismissPanGesture
    }
    
    func presentWithFlyingTransition(from content: NftDetailsFullScreenOverlayContent, in parentView: UIView,
                                     onPrepare: () -> Void, onDismiss: @escaping (DismissWay) -> Void) {
        guard state == .idle, superview == nil else {
            assertionFailure()
            return
        }

        self.onDismiss = onDismiss
        self.content = content
        state = .presenting
        backgroundColor = .clear

        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
        ])
        parentView.layoutIfNeeded()
                        
        let startFrame = content.convert(content.bounds, to: contentContainerView).applying(content.transform.inverted())
        let endFrame = contentContainerView.bounds
        content.addToParent(contentContainerView, bindToTop: false, yConstant: startFrame.midY - endFrame.midY)
        layoutIfNeeded()
        
        Haptics.play(.transition)

        UIView.animate(withDuration: 0.35) {
            content.transform = .identity
            self.backgroundColor = .black
        }

        onPrepare()
        content.centerYConstraint?.constant = 0
        UIView.animate(
            withDuration: 0.48,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.45,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: {
                self.layoutIfNeeded()
            },
            completion: { _ in
                self.state = .normal
            }
        )
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        if scrollView.zoomScale == 1.0 {
            dismiss(.singleTap)
        }
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gr.location(in: contentContainerView)
            let zoomRect = zoomRect(for: doubleTapZoomScale, centeredAt: point)
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    private func zoomRect(for scale: CGFloat, centeredAt point: CGPoint) -> CGRect {
        let w = scrollView.bounds.width / scale
        let h = scrollView.bounds.height / scale
        return CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
    }

    @objc private func handleDismissPan(_ gr: UIPanGestureRecognizer) {
        guard scrollView.zoomScale == scrollView.minimumZoomScale else { return }
        switch gr.state {
        case .ended, .cancelled:
            break
        default:
            return
        }

        let velocity = gr.velocity(in: scrollView)
        let translation = gr.translation(in: scrollView)
        let verticalDominant = abs(velocity.y) >= abs(velocity.x) * 0.85
        let flickUp = velocity.y < -420
        let flickDown = velocity.y > 420
        let draggedUp = translation.y < -56 && velocity.y < -80
        guard verticalDominant, flickUp || draggedUp || flickDown else { return }

        dismiss(flickDown ? .throwDown : (flickUp ? .throwUp : .normal))
    }
    
    enum DismissWay {
        case normal, throwUp, throwDown, singleTap
    }

    @discardableResult
    func dismiss(_ way: DismissWay = .normal) -> Bool {
        guard state == .normal, let content else { return false }
        state = .dismissing
        
        Haptics.play(.transition)
        
        let currentCenter = contentContainerView.convert(contentContainerView.bounds.center, to: self)
        content.addToParent(self, bindToTop: true, yConstant: currentCenter.y)
        
        layoutIfNeeded()
        
        onDismiss?(way)
        return true
    }
}

extension NftDetailsFullScreenOverlay: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === dismissPanGesture && otherGestureRecognizer === scrollView.panGestureRecognizer
    }
}

extension NftDetailsFullScreenOverlay: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentContainerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if state == .normal {
            updateBackground()
        }
    }
}
