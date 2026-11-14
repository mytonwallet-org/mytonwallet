import UIKit
import WalletContext

/// A full-screen viewer that pages through pictures, as Telegram's gallery does, built from the NFT viewer's zoom
/// stage and motion. A swipe pages, and so does a tap at the left or right edge, which darkens as it is pressed; a tap
/// elsewhere shows or hides the bars. Each picture zooms as an NFT does. The viewer opens out of the picture in the list
/// and closes back into it, and a swipe down closes it.
///
/// The bars are Telegram's: the back button, "N of M" over the picture's date on a capsule, and a footer with the
/// picture's caption over its buttons.
@MainActor
public final class MediaViewer: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    public struct Picture {
        public let url: URL?
        /// The picture as the list shows it, for the opening to start from
        public let image: UIImage?
        /// What VoiceOver reads for the picture
        public let title: String?
        public let details: Details?

        public init(url: URL?, image: UIImage? = nil, title: String?, details: Details? = nil) {
            self.url = url
            self.image = image
            self.title = title
            self.details = details
        }
    }

    /// The view in the list that shows the picture at an index, which the viewer opens from and closes into while it
    /// is on screen
    public typealias SourceProvider = (Int) -> UIImageView?

    /// Telegram's gap between the pages as they slide
    private static let pageGap: CGFloat = 20
    /// Telegram's gradient over the edge being pressed
    private static let edgeFadeWidth: CGFloat = 70
    /// The proportions a picture is shown at until it loads
    private static let placeholderRatio: CGFloat = 9 / 16
    /// How far a swipe down goes before the bars are gone, as in Telegram
    private static let chromeFadeDistance: CGFloat = 50
    /// Telegram's gallery brings its backdrop and its bars in together over 0.15 s, linearly, so its bars come over the
    /// list's as the backdrop covers them, and takes both away over 0.1 s
    static let appearanceDuration: TimeInterval = 0.15
    static let disappearanceDuration: TimeInterval = 0.1

    public private(set) var currentIndex: Int
    public var onClose: (() -> Void)?
    /// Whether a tap has hidden the bars
    public private(set) var isChromeHidden = false

    let pictures: [Picture]
    private let sourceProvider: SourceProvider
    private let pagerView = UIScrollView()
    private var pages: [Int: Page] = [:]
    private let headerShadeView = MediaViewerShadeView(isTop: true, opacity: 0.65)
    private(set) lazy var headerView = MediaViewerHeaderView { [weak self] in self?.close() }
    let footerView = MediaViewerFooterView()
    private let toastContainerView = MediaViewerPassthroughView()
    private let leadingEdgeFade = UIView()
    private let trailingEdgeFade = UIView()
    private lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
    private lazy var edgeTouch = MediaViewerTouchRecognizer(target: self, action: #selector(handleEdgeTouch(_:)))
    private lazy var edgeTap = UITapGestureRecognizer(target: self, action: #selector(handleEdgeTap(_:)))
    /// Whether the bars show for the viewer's own motion: hidden until the opening and from the closing
    private var isChromeInPlay = false
    private var isClosing = false
    /// How much of the bars a swipe down leaves
    private var chromeFade: CGFloat = 1
    /// The source of the current picture, hidden while the viewer shows it
    private weak var hiddenSource: UIImageView?
    private var isLayingOutPages = false
    /// Holds the picture flying between the list and the viewer, under the list's header until the viewer covers it
    private let flightHostView = UIView()
    /// The picture flying in from the list until it lands, which a closing started meanwhile turns back
    private weak var openingFlightView: UIView?
    private let flightMask = CALayer()
    /// The part of the flight over the list's header, shown as the viewer's backdrop covers the header
    private let flightHeaderMask = CALayer()
    private let flightContentMask = CALayer()
    /// Where the list's header ends in the viewer, taken as the viewer opens
    private var listContentTop: CGFloat?
    /// The navigation bar over the list, which the viewer's bar stands level with
    private weak var listNavigationBar: UINavigationBar?
    /// A second copy of the flying picture inside the list, over its content and under its header, as Telegram's
    /// gallery puts one on the chat's transition surface: the header's glass shows it where the list's picture was
    /// until the viewer's backdrop covers the header, and again as the backdrop goes
    private(set) var surfaceCopy: UIView?

    /// The toasts of actions run in the viewer, over its picture and above its buttons
    public private(set) lazy var toastController = ToastController(containerView: toastContainerView)

    @MainActor
    private final class Page {
        let zoomView = MediaZoomView(frame: .zero)
        let imageView = WImageView()
    }

    /// Opens the viewer over `window` at the picture `index`
    @discardableResult
    public static func present(
        pictures: [Picture],
        index: Int,
        in window: UIWindow,
        source: @escaping SourceProvider
    ) -> MediaViewer? {
        guard pictures.indices.contains(index) else { return nil }
        let viewer = MediaViewer(pictures: pictures, index: index, source: source)
        viewer.listNavigationBar = source(index).flatMap(getNavigationBar(of:))
        viewer.frame = window.bounds
        viewer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(viewer)
        viewer.layoutIfNeeded()
        viewer.open()
        return viewer
    }

    private init(pictures: [Picture], index: Int, source: @escaping SourceProvider) {
        self.pictures = pictures
        currentIndex = index
        sourceProvider = source
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        isLayingOutPages = true
        defer { isLayingOutPages = false }
        pagerView.frame = bounds.insetBy(dx: -Self.pageGap, dy: 0)
        pagerView.contentSize = CGSize(width: pagerView.bounds.width * CGFloat(pictures.count), height: bounds.height)
        if !pagerView.isDragging, !pagerView.isDecelerating {
            pagerView.contentOffset.x = pagerView.bounds.width * CGFloat(currentIndex)
        }
        updatePages()
        leadingEdgeFade.frame = CGRect(x: 0, y: 0, width: Self.edgeFadeWidth, height: bounds.height)
        trailingEdgeFade.frame = CGRect(x: bounds.width - Self.edgeFadeWidth, y: 0, width: Self.edgeFadeWidth, height: bounds.height)
        flightHostView.frame = bounds
        layoutChrome()
    }

    // MARK: Bars

    private var isRightToLeft: Bool {
        (window ?? superview)?.traitCollection.layoutDirection == .rightToLeft
    }

    /// The height of Telegram's bar over the status bar
    private var barHeight: CGFloat {
        safeAreaInsets.top + MediaViewerHeaderView.barHeight
    }

    /// Whether the bars' controls show: a tap hides them, a swipe down fades them, and they come with the opening and go
    /// with the closing
    private var isChromeShown: Bool {
        isChromeInPlay && !isChromeHidden && chromeFade > 0.5
    }

    /// Lays the bars out, moved out of the screen while a tap hides them, as Telegram's slide out
    private func layoutChrome() {
        let isRightToLeft = isRightToLeft
        let direction: UISemanticContentAttribute = isRightToLeft ? .forceRightToLeft : .forceLeftToRight
        for view in [headerView, footerView] as [UIView] where view.semanticContentAttribute != direction {
            view.semanticContentAttribute = direction
        }
        let slidesOut = isChromeHidden && !UIAccessibility.isReduceMotionEnabled
        let headerY = slidesOut ? -barHeight : 0
        headerShadeView.frame = CGRect(x: 0, y: headerY, width: bounds.width, height: barHeight + 70)
        headerView.frame = CGRect(x: 0, y: headerY, width: bounds.width, height: barHeight)
        let row = getHeaderRow()
        headerView.layout(safeArea: safeAreaInsets, rowY: row.minY, leadingInset: row.leadingInset, isRightToLeft: isRightToLeft)

        let isLandscape = bounds.width > bounds.height
        // A compact landscape viewer leaves its picture the room of the caption, as Telegram's
        let showsCaption = traitCollection.horizontalSizeClass == .regular || !isLandscape
        let layout = footerView.measure(size: bounds.size, safeArea: safeAreaInsets, showsCaption: showsCaption)
        let footerY = bounds.height - layout.panelHeight + (slidesOut ? MediaViewerFooterView.getHiddenOffset(isLandscape: isLandscape) : 0)
        footerView.frame = CGRect(x: 0, y: footerY, width: bounds.width, height: layout.panelHeight)
        footerView.layoutContent(safeArea: safeAreaInsets, isRightToLeft: isRightToLeft)
        let buttonsTop = bounds.height - safeAreaInsets.bottom - 8 - MediaViewerFooterLayout.buttonHeight - 8
        toastContainerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, buttonsTop))
    }

    /// Where the bar's row of 44 pt buttons stands, in the header's coordinates as it shows, and how far the back button
    /// stands from the safe area's leading edge: level with the navigation bar over the list, which puts its buttons at
    /// its top, on that bar's leading button where it is a 44 pt one, as the Agent's headers have. With no bar there, the
    /// row stands where a navigation bar starts, under the status bar. The row follows the bar wherever the status bar
    /// leaves it.
    private func getHeaderRow() -> (minY: CGFloat, leadingInset: CGFloat?) {
        let size = MediaViewerButtonGroup.itemSize
        guard let bar = listNavigationBar, let window, bar.window === window, !bar.isHidden, bar.bounds.height > 0 else {
            let statusBarHeight = window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
            return (max(safeAreaInsets.top, statusBarHeight), nil)
        }
        let barFrame = bar.convert(bar.bounds, to: self)
        guard let button = bar.topItem?.leftBarButtonItem?.customView, button.window === window,
              abs(button.bounds.width - size) < 0.5, abs(button.bounds.height - size) < 0.5 else {
            return (barFrame.minY, nil)
        }
        let frame = button.convert(button.bounds, to: self)
        // The bar may stand in a pane of a split view while the viewer covers the screen: the button's inset carries
        // over from the bar's own safe area, as far as a bar's inset reaches
        let inset = isRightToLeft
            ? barFrame.maxX - bar.safeAreaInsets.right - frame.maxX
            : frame.minX - barFrame.minX - bar.safeAreaInsets.left
        let maxInset = MediaViewerHeaderView.sideInset * 2
        return (frame.minY, inset >= 0 && inset <= maxInset ? inset : nil)
    }

    /// The navigation bar over the list that shows `source`
    private static func getNavigationBar(of source: UIView) -> UINavigationBar? {
        var responder: UIResponder? = source
        while let current = responder {
            if let controller = current as? UIViewController {
                guard let navigationController = controller.navigationController, !navigationController.isNavigationBarHidden else {
                    return nil
                }
                return navigationController.navigationBar
            }
            responder = current.next
        }
        return nil
    }

    /// Shows the bars' glass and fades their shades to match the viewer's state; call it in an animation block to animate
    private func applyChromeAppearance() {
        let isShown = isChromeShown
        if headerView.isShown != isShown {
            headerView.setShown(isShown)
        }
        if footerView.isShown != isShown {
            footerView.setShown(isShown)
        }
        let alpha = isChromeInPlay && !isChromeHidden ? chromeFade : 0
        headerShadeView.alpha = alpha * 0.5
        footerView.setContentAlpha(alpha)
    }

    /// Hides the bars or shows them again, as a tap on the picture does: they slide out of the screen and fade over
    /// Telegram's 0.3 s
    public func setChromeHidden(_ isHidden: Bool, animated: Bool) {
        guard isChromeHidden != isHidden else { return }
        isChromeHidden = isHidden
        guard animated else {
            applyChromeAppearance()
            layoutChrome()
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            self.applyChromeAppearance()
        }
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.layoutChrome()
        }
    }

    /// "N of M" over the pictures, for a viewer of more than one
    var counterText: String? {
        pictures.count > 1 ? L10n.agentWalletPageIndicator(current: currentIndex + 1, total: pictures.count) : nil
    }

    private func updateChromeContent(direction: MediaViewerAnimatedLabel.Direction, animated: Bool) {
        let details = pictures[currentIndex].details
        headerView.configure(counter: counterText, date: details?.date, direction: direction, animated: animated)
        headerView.configureMenu(details?.menu)
        footerView.configure(with: details)
        setNeedsLayout()
    }

    /// The bars' controls, which take touches while they show
    func isOnChrome(_ point: CGPoint) -> Bool {
        guard isChromeShown else { return false }
        return headerView.containsControl(at: convert(point, to: headerView)) || footerView.frame.contains(point)
    }

    // MARK: Paging

    /// Shows the picture `index`, as a swipe or an edge tap does
    public func showPicture(at index: Int) {
        guard pictures.indices.contains(index), index != currentIndex else { return }
        let previousIndex = currentIndex
        currentIndex = index
        pagerView.contentOffset.x = pagerView.bounds.width * CGFloat(index)
        updatePages()
        currentPageDidChange(from: previousIndex)
    }

    private func updatePages() {
        let pageWidth = pagerView.bounds.width
        guard pageWidth > 0 else { return }
        let visible = Set((currentIndex - 1...currentIndex + 1).filter { pictures.indices.contains($0) })
        for (index, page) in pages where !visible.contains(index) {
            page.zoomView.removeFromSuperview()
            pages.removeValue(forKey: index)
        }
        for index in visible {
            let page = pages[index] ?? makePage(at: index)
            let frame = CGRect(x: pageWidth * CGFloat(index) + Self.pageGap, y: 0, width: bounds.width, height: bounds.height)
            // Bounds and center stay valid under the transform a swipe down gives the page, unlike its frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if page.zoomView.bounds.size != frame.size || page.zoomView.center != center {
                page.zoomView.setZoomScale(1, animated: false)
                page.zoomView.bounds.size = frame.size
                page.zoomView.center = center
            }
            page.zoomView.updateContentSize()
            page.zoomView.layoutIfNeeded()
            page.zoomView.centerContent()
        }
    }

    private func makePage(at index: Int) -> Page {
        let page = Page()
        let picture = pictures[index]
        page.zoomView.semanticContentAttribute = .forceLeftToRight
        // A zoomed picture stays on its own page instead of reaching over the next one
        page.zoomView.clipsToBounds = true
        page.zoomView.fitting = .aspectFit(Self.getRatio(of: picture.image))
        page.imageView.contentMode = .scaleAspectFill
        page.imageView.clipsToBounds = true
        page.imageView.isAccessibilityElement = true
        page.imageView.accessibilityTraits = .image
        page.imageView.accessibilityLabel = picture.title
        page.imageView.translatesAutoresizingMaskIntoConstraints = false
        page.zoomView.contentContainerView.addSubview(page.imageView)
        NSLayoutConstraint.activate([
            page.imageView.topAnchor.constraint(equalTo: page.zoomView.contentContainerView.topAnchor),
            page.imageView.leadingAnchor.constraint(equalTo: page.zoomView.contentContainerView.leadingAnchor),
            page.imageView.trailingAnchor.constraint(equalTo: page.zoomView.contentContainerView.trailingAnchor),
            page.imageView.bottomAnchor.constraint(equalTo: page.zoomView.contentContainerView.bottomAnchor),
        ])
        if let image = picture.image {
            page.imageView.image = image
        } else {
            page.imageView.loadImage(url: picture.url) { [weak self, weak page] didLoad in
                guard didLoad, let self, let page else { return }
                page.zoomView.fitting = .aspectFit(Self.getRatio(of: page.imageView.image))
                page.zoomView.updateContentSize()
                page.zoomView.layoutIfNeeded()
                page.zoomView.centerContent()
                self.setNeedsLayout()
            }
        }
        pagerView.addSubview(page.zoomView)
        pages[index] = page
        return page
    }

    private static func getRatio(of image: UIImage?) -> CGFloat {
        guard let size = image?.size, size.width > 0, size.height > 0 else { return placeholderRatio }
        return size.height / size.width
    }

    /// Shows the bars' content of the current page, changing it from the one of `previousIndex`, if any
    private func currentPageDidChange(from previousIndex: Int?) {
        // The list's picture of the shown page gives way to it, as Telegram's thumbnail does
        hiddenSource?.alpha = 1
        hiddenSource = sourceProvider(currentIndex)
        hiddenSource?.alpha = 0
        let isForward = previousIndex.map { $0 < currentIndex } ?? true
        updateChromeContent(direction: isForward ? .forward : .backward, animated: previousIndex != nil)
        UIAccessibility.post(notification: .layoutChanged, argument: pages[currentIndex]?.imageView)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pagerView, !isLayingOutPages, pagerView.bounds.width > 0 else { return }
        let index = Int((pagerView.contentOffset.x / pagerView.bounds.width).rounded())
        guard pictures.indices.contains(index), index != currentIndex else { return }
        let previousIndex = currentIndex
        currentIndex = index
        updatePages()
        currentPageDidChange(from: previousIndex)
    }

    /// The width at each side that a tap pages from, as in Telegram's gallery
    private var edgeWidth: CGFloat {
        min(44, (bounds.width / 6).rounded(.down))
    }

    private func getEdge(at point: CGPoint) -> Int? {
        guard pictures.count > 1 else { return nil }
        if point.x < edgeWidth, currentIndex > 0 { return -1 }
        if point.x > bounds.width - edgeWidth, currentIndex < pictures.count - 1 { return 1 }
        return nil
    }

    /// A tap at an edge pages at once, as in Telegram's gallery, without waiting to see whether it is a double tap
    @objc func handleEdgeTap(_ gesture: UITapGestureRecognizer) {
        guard !isClosing, let edge = getEdge(at: gesture.location(in: self)) else { return }
        showPicture(at: currentIndex + edge)
    }

    /// A tap elsewhere hides the bars or shows them again
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isClosing else { return }
        setChromeHidden(!isChromeHidden, animated: true)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let page = pages[currentIndex] else { return }
        page.zoomView.toggleZoom(at: gesture.location(in: page.zoomView.contentContainerView))
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // The bars' controls keep their touches, as Telegram's gallery leaves its interactive controls alone
        if isOnChrome(touch.location(in: self)) { return false }
        guard gestureRecognizer is UITapGestureRecognizer else { return true }
        let isAtEdge = getEdge(at: touch.location(in: self)) != nil
        return gestureRecognizer === edgeTap ? isAtEdge : !isAtEdge
    }

    /// Darkens the edge being pressed, as Telegram's gallery does: in over 0.08 s and out over 0.16 s, until the finger
    /// lifts or moves
    @objc private func handleEdgeTouch(_ recognizer: MediaViewerTouchRecognizer) {
        updateEdgeFade(isTouching: recognizer.isTouching, at: recognizer.location(in: self))
    }

    /// Darkens the edge under a finger at `point` that is down and hasn't moved, when there is a picture beyond it
    func updateEdgeFade(isTouching: Bool, at point: CGPoint) {
        let edge = isTouching && !isClosing ? getEdge(at: point) : nil
        for (fade, side) in [(leadingEdgeFade, -1), (trailingEdgeFade, 1)] {
            let alpha: CGFloat = edge == side ? 1 : 0
            guard fade.alpha != alpha else { continue }
            guard !UIAccessibility.isReduceMotionEnabled else {
                fade.alpha = alpha
                continue
            }
            UIView.animate(withDuration: alpha > 0 ? 0.08 : 0.16, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                fade.alpha = alpha
            }
        }
    }

    /// The edge darkening of `side`, -1 for the left and 1 for the right
    func getEdgeFadeAlpha(side: Int) -> CGFloat {
        side < 0 ? leadingEdgeFade.alpha : trailingEdgeFade.alpha
    }

    // MARK: Opening and closing

    private func open() {
        let source = sourceProvider(currentIndex)
        listContentTop = source.flatMap(getListContentTop(of:))
        currentPageDidChange(from: nil)
        guard let page = pages[currentIndex] else { return }
        Haptics.play(.transition)
        // The bars fade in with the backdrop as the picture flies out of the list
        UIView.animate(withDuration: Self.appearanceDuration, delay: 0, options: [.curveLinear, .allowUserInteraction]) {
            self.isChromeInPlay = true
            self.applyChromeAppearance()
        }
        // Reduce Motion is checked first, since making the flight already puts its picture over the viewer
        guard !UIAccessibility.isReduceMotionEnabled, let flight = makeFlight(from: source, to: page) else {
            backgroundColor = .black
            alpha = 0
            UIView.animate(withDuration: MediaViewerMotion.duration) { self.alpha = 1 }
            return
        }
        page.zoomView.isHidden = true
        openingFlightView = flight.view
        backgroundColor = .clear
        UIView.animate(withDuration: Self.appearanceDuration, delay: 0, options: [.beginFromCurrentState, .curveLinear]) {
            self.backgroundColor = .black
        }
        keepFlightUnderListHeader(fadingHeaderTo: 1, over: Self.appearanceDuration)
        let surfaceFlight = source.flatMap { makeSurfaceCopy(in: $0, image: flight.image, from: flight.frame, cornerRadius: $0.layer.cornerRadius) }
        UIView.animate(
            withDuration: MediaViewerMotion.duration,
            delay: 0,
            usingSpringWithDamping: MediaViewerMotion.damping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState]
        ) {
            flight.view.frame = flight.target
            flight.view.layer.cornerRadius = 0
            surfaceFlight?.land(at: flight.target, cornerRadius: 0)
        } completion: { _ in
            flight.view.removeFromSuperview()
            // A closing started during the flight owns the page, the list's copy and the mask from then on
            guard !self.isClosing else { return }
            page.zoomView.isHidden = false
            self.removeSurfaceCopy()
            self.flightHostView.layer.mask = nil
        }
    }

    /// Closes the viewer for a screen that opens over the list: it fades out as that screen comes in, without its
    /// picture flying back into the list
    public func closeFading() {
        guard !isClosing else { return }
        isClosing = true
        hiddenSource?.alpha = 1
        let finish = { [weak self] in
            guard let self else { return }
            self.removeSurfaceCopy()
            self.removeFromSuperview()
            self.onClose?()
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            finish()
            return
        }
        UIView.animate(withDuration: Self.fadingCloseDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.alpha = 0
        } completion: { _ in finish() }
    }

    /// As long as the in-app browser takes to come up over the list
    private static let fadingCloseDuration: TimeInterval = 0.35

    /// Closes the viewer, into the list's picture of the current page while it is on screen
    public func close(throwingBy velocityY: CGFloat = 0) {
        guard !isClosing else { return }
        isClosing = true
        Haptics.play(.transition)
        let page = pages[currentIndex]
        let source = sourceProvider(currentIndex)
        let finish = { [weak self] in
            guard let self else { return }
            self.hiddenSource?.alpha = 1
            self.removeSurfaceCopy()
            self.removeFromSuperview()
            self.onClose?()
        }
        // The bars and the backdrop go together, as in Telegram
        UIView.animate(withDuration: Self.disappearanceDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.isChromeInPlay = false
            self.applyChromeAppearance()
            self.leadingEdgeFade.alpha = 0
            self.trailingEdgeFade.alpha = 0
        }
        UIView.animate(withDuration: Self.disappearanceDuration, delay: 0, options: [.beginFromCurrentState, .curveLinear]) {
            self.backgroundColor = .clear
        }
        guard let page, !UIAccessibility.isReduceMotionEnabled else {
            UIView.animate(withDuration: MediaViewerMotion.collapseDuration, animations: { self.alpha = 0 }) { _ in finish() }
            return
        }
        // A picture still flying in turns back from where it is
        let frame = openingFlightView?.layer.presentation()?.frame ?? page.imageView.convert(page.imageView.bounds, to: self)
        openingFlightView?.removeFromSuperview()
        let flyingView = makeFlyingView(image: page.imageView.image, frame: frame, cornerRadius: 0, maskedCorners: [])
        page.zoomView.isHidden = true
        keepFlightUnderListHeader(fadingHeaderTo: 0, over: Self.disappearanceDuration)
        guard let source, source.window != nil else {
            // The list's picture is off screen: the picture leaves in the direction it was thrown, or fades
            let direction: CGFloat = velocityY < 0 ? -1 : 1
            UIView.animate(withDuration: MediaViewerMotion.collapseDuration, delay: 0, options: [.curveEaseIn]) {
                if velocityY == 0 {
                    flyingView.alpha = 0
                    flyingView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                } else {
                    flyingView.center.y += direction * self.bounds.height
                }
            } completion: { _ in finish() }
            return
        }
        let target = source.convert(source.bounds, to: self)
        let surfaceFlight = makeSurfaceCopy(in: source, image: page.imageView.image, from: frame, cornerRadius: 0)
        UIView.animate(
            withDuration: MediaViewerMotion.collapseDuration,
            delay: 0,
            usingSpringWithDamping: MediaViewerMotion.damping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState]
        ) {
            flyingView.frame = target
            flyingView.layer.cornerRadius = source.layer.cornerRadius
            flyingView.layer.maskedCorners = source.layer.maskedCorners
            surfaceFlight?.land(at: target, cornerRadius: source.layer.cornerRadius)
        } completion: { _ in finish() }
    }

    /// A copy of the picture over `page`'s place, starting from where the list shows it
    private func makeFlight(from source: UIImageView?, to page: Page) -> (view: UIView, image: UIImage, frame: CGRect, target: CGRect)? {
        guard let source, source.window != nil, let image = source.image ?? page.imageView.image else { return nil }
        layoutIfNeeded()
        let target = page.imageView.convert(page.imageView.bounds, to: self)
        let frame = source.convert(source.bounds, to: self)
        guard target.width > 0, frame.width > 0 else { return nil }
        let view = makeFlyingView(
            image: image,
            frame: frame,
            cornerRadius: source.layer.cornerRadius,
            maskedCorners: source.layer.maskedCorners
        )
        return (view, image, frame, target)
    }

    private func makeFlyingView(image: UIImage?, frame: CGRect, cornerRadius: CGFloat, maskedCorners: CACornerMask) -> UIView {
        let container = UIView(frame: frame)
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        container.layer.cornerRadius = cornerRadius
        container.layer.maskedCorners = maskedCorners
        container.layer.cornerCurve = .continuous
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.frame = container.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(imageView)
        flightHostView.addSubview(container)
        return container
    }

    /// The flight's copy inside the list, for the flight's animation block to move along with the flight
    @MainActor
    private struct SurfaceFlight {
        let view: UIView
        let viewer: MediaViewer

        /// Moves the copy to `frame` of the viewer
        func land(at frame: CGRect, cornerRadius: CGFloat) {
            guard let surface = view.superview else { return }
            view.frame = viewer.convert(frame, to: surface)
            view.layer.cornerRadius = cornerRadius
        }
    }

    /// Puts a copy of the flight at `frame` of the viewer into the list that shows `source`, just over the list's scroll
    /// view, under the header and the other bars over it, as Telegram's gallery adds one to the chat's transition surface
    private func makeSurfaceCopy(in source: UIView, image: UIImage?, from frame: CGRect, cornerRadius: CGFloat) -> SurfaceFlight? {
        removeSurfaceCopy()
        guard source.window != nil, let scrollView = getScrollView(around: source), let surface = scrollView.superview else {
            return nil
        }
        let view = makeFlyingView(
            image: image,
            frame: convert(frame, to: surface),
            cornerRadius: cornerRadius,
            maskedCorners: source.layer.maskedCorners
        )
        surface.insertSubview(view, aboveSubview: scrollView)
        surfaceCopy = view
        return SurfaceFlight(view: view, viewer: self)
    }

    private func removeSurfaceCopy() {
        surfaceCopy?.removeFromSuperview()
        surfaceCopy = nil
    }

    private func getScrollView(around source: UIView) -> UIScrollView? {
        var view = source.superview
        while let current = view {
            if let scrollView = current as? UIScrollView { return scrollView }
            view = current.superview
        }
        return nil
    }

    /// Where the header over the list that shows `source` ends, in the viewer's coordinates: the top of the content area
    /// of the scroll view around it
    private func getListContentTop(of source: UIView) -> CGFloat? {
        guard let scrollView = getScrollView(around: source) else { return nil }
        let top = scrollView.convert(CGPoint(x: 0, y: scrollView.bounds.minY + scrollView.adjustedContentInset.top), to: self).y
        return top > 0.5 ? top : nil
    }

    /// Shows the flight only below the list's header, and over the header only as much as the viewer's backdrop covers
    /// it: from none to all of it as the viewer opens, and back as it closes, so the header is never drawn under the
    /// picture while it shows
    private func keepFlightUnderListHeader(fadingHeaderTo opacity: Float, over duration: TimeInterval) {
        guard let listContentTop else { return }
        let top = min(listContentTop, bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flightMask.frame = bounds
        flightHeaderMask.frame = CGRect(x: 0, y: 0, width: bounds.width, height: top)
        flightContentMask.frame = CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top)
        let startOpacity = flightHostView.layer.mask === flightMask
            ? flightHeaderMask.presentation()?.opacity ?? flightHeaderMask.opacity
            : 1 - opacity
        flightHeaderMask.removeAllAnimations()
        flightHeaderMask.opacity = opacity
        flightHostView.layer.mask = flightMask
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = startOpacity
        animation.toValue = opacity
        animation.duration = duration
        // In step with the backdrop
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        flightHeaderMask.add(animation, forKey: "opacity")
    }

    /// The flight's mask over the list's header, while the flight keeps under it
    var flightHeaderMaskState: (height: CGFloat, opacity: Float)? {
        guard flightHostView.layer.mask === flightMask else { return nil }
        return (flightHeaderMask.frame.height, flightHeaderMask.opacity)
    }

    /// How much of the flight shows over the list's header on the frame on screen
    var shownFlightHeaderOpacity: Float? {
        guard flightHostView.layer.mask === flightMask else { return nil }
        return flightHeaderMask.presentation()?.opacity ?? flightHeaderMask.opacity
    }

    public override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    public override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        switch direction {
        case .left, .next:
            guard currentIndex < pictures.count - 1 else { return false }
            showPicture(at: currentIndex + 1)
        case .right, .previous:
            guard currentIndex > 0 else { return false }
            showPicture(at: currentIndex - 1)
        default:
            return false
        }
        UIAccessibility.post(notification: .pageScrolled, argument: counterText ?? pictures[currentIndex].title)
        return true
    }

    // MARK: Swipe down

    @objc func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !isClosing, let page = pages[currentIndex] else { return }
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .began, .changed:
            // The pages keep still while the picture follows the finger down
            pagerView.isScrollEnabled = false
            page.zoomView.transform = MediaViewerMotion.getDismissTransform(for: translation, in: bounds)
            backgroundColor = UIColor.black.withAlphaComponent(MediaViewerMotion.getBackdropAlpha(for: translation))
            setChromeFade(1 - min(1, abs(translation.y) / Self.chromeFadeDistance))
        case .ended, .cancelled:
            pagerView.isScrollEnabled = true
            let velocity = gesture.velocity(in: self)
            if gesture.state == .ended, MediaViewerMotion.shouldDismiss(translation: translation, velocity: velocity, in: bounds) {
                close(throwingBy: velocity.y == 0 ? translation.y : velocity.y)
            } else {
                UIView.animate(
                    withDuration: MediaViewerMotion.duration,
                    delay: 0,
                    usingSpringWithDamping: MediaViewerMotion.damping,
                    initialSpringVelocity: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction]
                ) {
                    page.zoomView.transform = .identity
                    self.backgroundColor = .black
                    self.setChromeFade(1)
                }
            }
        default:
            break
        }
    }

    /// Fades the bars as a swipe down moves the picture, as Telegram's gallery does over 50 pt; their glass goes once
    /// they are half gone
    private func setChromeFade(_ fade: CGFloat) {
        let wasShown = isChromeShown
        chromeFade = fade
        guard wasShown != isChromeShown else {
            applyChromeAppearance()
            return
        }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.applyChromeAppearance()
        }
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan else { return true }
        let velocity = dismissPan.velocity(in: self)
        return !isClosing && pages[currentIndex]?.zoomView.isAtMinimumZoom != false && abs(velocity.y) > abs(velocity.x)
    }

    /// The edge's darkening watches every touch, and the swipe down starts over the pages' own pans, as the NFT
    /// viewer's starts over its zoom
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === edgeTouch || otherGestureRecognizer === edgeTouch { return true }
        return gestureRecognizer === dismissPan && otherGestureRecognizer is UIPanGestureRecognizer
    }

    // MARK: Setup

    private func setupViews() {
        accessibilityIdentifier = "MediaViewer"
        accessibilityViewIsModal = true
        semanticContentAttribute = .forceLeftToRight
        // Telegram's gallery is dark whatever the app's theme
        overrideUserInterfaceStyle = .dark
        backgroundColor = .black

        pagerView.isPagingEnabled = true
        pagerView.showsHorizontalScrollIndicator = false
        pagerView.showsVerticalScrollIndicator = false
        pagerView.contentInsetAdjustmentBehavior = .never
        pagerView.alwaysBounceHorizontal = true
        pagerView.clipsToBounds = false
        pagerView.scrollsToTop = false
        pagerView.delaysContentTouches = false
        pagerView.semanticContentAttribute = .forceLeftToRight
        pagerView.isDirectionalLockEnabled = true
        pagerView.delegate = self
        addSubview(pagerView)

        for (fade, isLeading) in [(leadingEdgeFade, true), (trailingEdgeFade, false)] {
            fade.isUserInteractionEnabled = false
            fade.alpha = 0
            let gradient = CAGradientLayer()
            gradient.colors = [UIColor.black.withAlphaComponent(0.35).cgColor, UIColor.black.withAlphaComponent(0).cgColor]
            gradient.startPoint = CGPoint(x: isLeading ? 0 : 1, y: 0.5)
            gradient.endPoint = CGPoint(x: isLeading ? 1 : 0, y: 0.5)
            gradient.frame = CGRect(x: 0, y: 0, width: Self.edgeFadeWidth, height: 4000)
            fade.layer.addSublayer(gradient)
            addSubview(fade)
        }

        flightHostView.isUserInteractionEnabled = false
        addSubview(flightHostView)
        for layer in [flightHeaderMask, flightContentMask] {
            layer.backgroundColor = UIColor.black.cgColor
            flightMask.addSublayer(layer)
        }
        addSubview(headerShadeView)
        addSubview(footerView)
        addSubview(headerView)
        addSubview(toastContainerView)
        footerView.onCaptionScroll = { [weak self] in self?.layoutChrome() }
        // The bars come with the opening
        headerView.setShown(false)
        footerView.setShown(false)
        headerShadeView.alpha = 0
        footerView.setContentAlpha(0)
        accessibilityElements = [headerView, pagerView, footerView]

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)
        tap.delegate = self
        addGestureRecognizer(tap)
        edgeTap.delegate = self
        addGestureRecognizer(edgeTap)
        dismissPan.delegate = self
        dismissPan.maximumNumberOfTouches = 1
        addGestureRecognizer(dismissPan)
        edgeTouch.delegate = self
        addGestureRecognizer(edgeTouch)
    }
}

/// Follows a touch from the moment it lands until it lifts or moves, as Telegram's tap recognizer gives up on a finger
/// that moves over 2 pt, without taking the touch from other recognizers
@MainActor
final class MediaViewerTouchRecognizer: UIGestureRecognizer {
    private static let maxTapMovement: CGFloat = 2

    private(set) var isTouching = false
    private var startLocation: CGPoint?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        startLocation = touches.first?.location(in: view)
        isTouching = true
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let startLocation, let location = touches.first?.location(in: view),
           hypot(location.x - startLocation.x, location.y - startLocation.y) > Self.maxTapMovement {
            isTouching = false
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        isTouching = false
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        isTouching = false
        state = .cancelled
    }

    override func reset() {
        isTouching = false
        startLocation = nil
        super.reset()
    }
}
