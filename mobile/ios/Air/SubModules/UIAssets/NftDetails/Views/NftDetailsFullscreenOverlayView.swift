import UIKit
import Kingfisher
import WalletContext
import UIComponents

final class NftDetailsFullscreenOverlayView: UIView {

    var onDismiss: (() -> Void)?

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 3.0
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.bouncesZoom = true
        sv.bounces = true
        sv.alwaysBounceVertical = true
        sv.contentInsetAdjustmentBehavior = .never
        return sv
    }()

    private let contentContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .large)
        s.color = .white
        s.hidesWhenStopped = true
        return s
    }()

    private weak var flyingTransitionSourceView: UIView?

    private var isDismissing = false
    private var isAppearing = false
    private var currentModel: NftDetailsItemModel?
    private var containerWidthConstraint: NSLayoutConstraint!
    private var containerHeightConstraint: NSLayoutConstraint!
    
    /// Dismiss via upward pan. `UISwipeGestureRecognizer` loses to `UIScrollView`’s pan (and bounce); this pan runs simultaneously.
    private lazy var dismissPanGesture: UIPanGestureRecognizer = {
        let p = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        p.delegate = self
        p.cancelsTouchesInView = false
        return p
    }()

    init(models: [NftDetailsItemModel], currentIndex: Int) {
        super.init(frame: .zero)
        backgroundColor = .black

        setupScrollView()
        setupGestures()

        let model = models[currentIndex]
        configure(with: model)
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

        let image = imageView.image
        let imageSize = image?.size ?? CGSize(width: bounds.width, height: bounds.width)
        let aspectRatio = imageSize.width > 0 ? imageSize.height / imageSize.width : 1

        let availableWidth = bounds.width
        let availableHeight = bounds.height

        let fittedWidth: CGFloat
        let fittedHeight: CGFloat

        if availableWidth * aspectRatio <= availableHeight {
            fittedWidth = availableWidth
            fittedHeight = availableWidth * aspectRatio
        } else {
            fittedHeight = availableHeight
            fittedWidth = availableHeight / aspectRatio
        }

        containerWidthConstraint.constant = fittedWidth
        containerHeightConstraint.constant = fittedHeight
        scrollView.contentSize = CGSize(width: fittedWidth, height: fittedHeight)
    }

    private func centerContent() {
        let scrollSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize

        let hInset = max((scrollSize.width - contentSize.width) / 2, 0)
        let vInset = max((scrollSize.height - contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: vInset, left: hInset, bottom: vInset, right: hInset)
    }

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        scrollView.addSubview(contentContainerView)

        contentContainerView.addSubview(imageView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(spinner)
        
        containerWidthConstraint = contentContainerView.widthAnchor.constraint(equalToConstant: 300)
        containerHeightConstraint = contentContainerView.heightAnchor.constraint(equalToConstant: 300)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentContainerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            containerWidthConstraint,
            containerHeightConstraint,

            imageView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            
            spinner.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
        ])
    }

    private func setupGestures() {
        // Single tap on background dismisses when at base zoom.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        // Double-tap on content toggles zoom: resets to 1× if zoomed, zooms in if at 1×.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single tap must wait for double-tap to fail so they don't conflict.
        tap.require(toFail: doubleTap)

        scrollView.addGestureRecognizer(dismissPanGesture)
    }

    private func configure(with model: NftDetailsItemModel) {
        currentModel = model

        imageView.kf.cancelDownloadTask()
        imageView.image = nil

        if let urlString = model.item.thumbnailUrl?.nilIfEmpty, let url = URL(string: urlString) {
            spinner.startAnimating()
            imageView.kf.setImage(
                with: .network(url),
                placeholder: nil,
                options: [.alsoPrefetchToMemory, .cacheOriginalImage],
                completionHandler: { [weak self] result in
                    guard let self, self.currentModel === model else { return }
                    DispatchQueue.main.async {
                        self.spinner.stopAnimating()
                        switch result {
                        case .success:
                            break
                        case .failure:
                            self.imageView.image = NftDetailsImage.errorPlaceholderImage()
                        }
                        self.setNeedsLayout()
                    }
                }
            )
        } else {
            spinner.stopAnimating()
            imageView.image = NftDetailsImage.errorPlaceholderImage()
            setNeedsLayout()
        }
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        if scrollView.zoomScale == 1.0 {
            dismiss()
        }
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gr.location(in: contentContainerView)
            let zoomRect = zoomRect(for: scrollView.maximumZoomScale / 2, centeredAt: point)
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
        let draggedUp = translation.y < -56 && velocity.y < -80
        guard verticalDominant, flickUp || draggedUp else { return }

        dismiss()
    }

    func presentWithFadeIn(in parent: UIView) {
        isAppearing = true
        
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])

        alpha = 0
        Haptics.play(.transition)
        UIView.animate(withDuration: 0.25) {
            self.alpha = 1
            self.isAppearing = false
        }
    }

    func presentWithFlyingTransition(from sourceView: UIView, in containerView: UIView) {
        self.isAppearing = true

        translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: containerView.topAnchor),
            leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        alpha = 0
        scrollView.alpha = 0
        containerView.layoutIfNeeded()
        layoutIfNeeded()

        let startFrame = convert(sourceView.bounds, from: sourceView)
        let snapshotImage = self.snapshotImage(from: sourceView)

        guard let snapshotImage, startFrame.width > 0.5, startFrame.height > 0.5, bounds.width > 0.5, bounds.height > 0.5 else {
            flyingTransitionSourceView = nil
            scrollView.alpha = 1
            alpha = 0
            UIView.animate(withDuration: 0.25) {
                self.alpha = 1
            }
            return
        }

        flyingTransitionSourceView = sourceView
        let endFrame = aspectFitContentFrame(contentSize: snapshotImage.size, in: bounds)

        let flying = UIImageView(image: snapshotImage)
        flying.contentMode = .scaleAspectFit
        flying.clipsToBounds = true
        flying.frame = startFrame
        addSubview(flying)

        Haptics.play(.transition)
        
        UIView.animate(withDuration: 0.35) {
            self.alpha = 1
        }

        UIView.animate(
            withDuration: 0.58,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.45,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                flying.frame = endFrame
            },
            completion: { _ in
                self.setNeedsLayout()
                self.layoutIfNeeded()
                self.scrollView.alpha = 1
                UIView.animate(
                    withDuration: 0.25, delay: 0, animations: {
                        flying.alpha = 0.0
                    }, completion: { _ in
                       flying.removeFromSuperview()
                       self.isAppearing = false
                   }
                )
            }
        )
    }

    private func snapshotImage(from view: UIView) -> UIImage? {
        let b = view.bounds
        guard b.width > 0.5, b.height > 0.5 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: b, format: format)
        return renderer.image { _ in
            _ = view.drawHierarchy(in: b, afterScreenUpdates: true)
        }
    }

    private func aspectFitContentFrame(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        let availableWidth = bounds.width
        let availableHeight = bounds.height
        guard availableWidth > 0, availableHeight > 0 else { return .zero }

        let aspectRatio = contentSize.width > 0 ? contentSize.height / contentSize.width : 1

        let fittedWidth: CGFloat
        let fittedHeight: CGFloat

        if availableWidth * aspectRatio <= availableHeight {
            fittedWidth = availableWidth
            fittedHeight = availableWidth * aspectRatio
        } else {
            fittedHeight = availableHeight
            fittedWidth = availableHeight / aspectRatio
        }

        let x = (availableWidth - fittedWidth) / 2
        let y = (availableHeight - fittedHeight) / 2
        return CGRect(x: x, y: y, width: fittedWidth, height: fittedHeight)
    }

    func dismiss() {
        guard !isDismissing, !isAppearing else { return }
        imageView.kf.cancelDownloadTask()

        if scrollView.zoomScale == scrollView.minimumZoomScale,
           let source = flyingTransitionSourceView,
           source.window != nil,
           source.superview != nil,
           dismissWithFlyingTransition(to: source) {
           return
        }

        dismissWithFadeOnly()
    }

    private func dismissWithFadeOnly() {
        isDismissing = true
        Haptics.play(.transition)
        
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    private func dismissWithFlyingTransition(to sourceView: UIView) -> Bool {
        layoutIfNeeded()

        guard let snapshot = snapshotImage(from: contentContainerView) else { return false }

        let targetFrame = convert(sourceView.bounds, from: sourceView)
        guard targetFrame.width > 0.5, targetFrame.height > 0.5 else { return false }

        let startFrame = contentContainerView.convert(contentContainerView.bounds, to: self)
        guard startFrame.width > 0.5, startFrame.height > 0.5 else { return false }

        isDismissing = true
        scrollView.alpha = 0
        spinner.alpha = 0
        alpha = 1

        let flying = UIImageView(image: snapshot)
        flying.contentMode = .scaleAspectFit
        flying.clipsToBounds = true
        flying.frame = startFrame
        addSubview(flying)

        Haptics.play(.transition)

        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 0
            flying.frame = targetFrame
        } completion: { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
        return true
    }
}

extension NftDetailsFullscreenOverlayView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === dismissPanGesture && otherGestureRecognizer === scrollView.panGestureRecognizer
    }
}

extension NftDetailsFullscreenOverlayView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentContainerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }
}

