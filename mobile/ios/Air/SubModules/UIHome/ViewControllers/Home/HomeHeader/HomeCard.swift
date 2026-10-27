
import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception
import Dependencies
import UIKitNavigation

@MainActor
final class Container {
    var headerViewModel: HomeHeaderViewModel?
    var accountContext: AccountContext?
    var layout: HomeCardLayoutMetrics
    var minimumHomeCardFontScale: CGFloat

    init(headerViewModel: HomeHeaderViewModel? = nil, accountContext: AccountContext? = nil, layout: HomeCardLayoutMetrics = .screen, minimumHomeCardFontScale: CGFloat = 1) {
        self.headerViewModel = headerViewModel
        self.accountContext = accountContext
        self.layout = layout
        self.minimumHomeCardFontScale = minimumHomeCardFontScale
    }
}

final class HomeCard: UICollectionViewCell {

    let container = Container()

    // This stationary layer flattens the surface's 3D subtree above collapsed content.
    private let cardPresentation = UIView()
    private let cardSurface = UIView()
    private lazy var interaction = CardSurfaceInteraction(container: contentView, surface: cardSurface) { [weak self] in
        self?.cardBackground.setLight($0)
        self?.cardContent.setMotionLight($0, preset: self?.motionPreset)
    }
    private var motionObservation: ObserveToken?
    private var motionPreset: CardMotionPreset?
    private let cardBackground = HomeCardBackground()
    private let cardPromotion = HomeCardPromotionView()
    var cardContentMaskingContainer: UIView!
    private var cardContentClipTransform = CGAffineTransform.identity
    private let cardContent = HomeCardContentView(mode: .expanded)
    private let collapsedContent = HomeCardContentView(mode: .collapsed)
    private let miniatureContent = HomeCardMiniatureContent()
    private let miniatureTapButton = UIButton(type: .custom)
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!

    var observeToken: ObserveToken?
    private var tintObservation: ObserveToken?
    private var accessibilityObservation: ObserveToken?
    private var appliedHeaderState: HomeHeaderState?
    private var balanceAnimationDeadline: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup() {
        interaction.onPlayTouch = { [weak self] point in
            guard let self else { return }
            cardContent.setParticleInteractionPoint(point, from: contentView)
        }
        let layout = container.layout
        widthConstraint = contentView.widthAnchor.constraint(equalToConstant: layout.itemWidth)
        heightConstraint = contentView.heightAnchor.constraint(equalToConstant: layout.itemHeight).withPriority(.defaultHigh)
        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
        ])

        contentView.addSubview(collapsedContent)
        NSLayoutConstraint.activate([
            collapsedContent.topAnchor.constraint(equalTo: contentView.topAnchor),
            collapsedContent.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collapsedContent.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collapsedContent.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        cardPresentation.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardPresentation)
        NSLayoutConstraint.activate([
            cardPresentation.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardPresentation.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardPresentation.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardPresentation.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        cardSurface.translatesAutoresizingMaskIntoConstraints = false
        cardPresentation.addSubview(cardSurface)
        NSLayoutConstraint.activate([
            cardSurface.topAnchor.constraint(equalTo: cardPresentation.topAnchor),
            cardSurface.leadingAnchor.constraint(equalTo: cardPresentation.leadingAnchor),
            cardSurface.trailingAnchor.constraint(equalTo: cardPresentation.trailingAnchor),
            cardSurface.bottomAnchor.constraint(equalTo: cardPresentation.bottomAnchor),
        ])

        cardBackground.isAccessibilityElement = false
        cardBackground.accessibilityElementsHidden = true
        cardBackground.isUserInteractionEnabled = false
        cardSurface.addSubview(cardBackground)
        NSLayoutConstraint.activate([
            cardBackground.topAnchor.constraint(equalTo: cardSurface.topAnchor),
            cardBackground.leadingAnchor.constraint(equalTo: cardSurface.leadingAnchor),
            cardBackground.trailingAnchor.constraint(equalTo: cardSurface.trailingAnchor),
            cardBackground.bottomAnchor.constraint(equalTo: cardSurface.bottomAnchor),
        ])

        cardPromotion.isAccessibilityElement = false
        cardPromotion.accessibilityElementsHidden = true
        cardPromotion.isUserInteractionEnabled = false
        cardSurface.addSubview(cardPromotion)
        NSLayoutConstraint.activate([
            cardPromotion.topAnchor.constraint(equalTo: cardSurface.topAnchor),
            cardPromotion.leadingAnchor.constraint(equalTo: cardSurface.leadingAnchor),
            cardPromotion.trailingAnchor.constraint(equalTo: cardSurface.trailingAnchor),
            cardPromotion.bottomAnchor.constraint(equalTo: cardSurface.bottomAnchor),
        ])

        cardContentMaskingContainer = UIView()
        cardContentMaskingContainer.layer.cornerRadius = 26
        cardContentMaskingContainer.layer.cornerCurve = .continuous
        cardContentMaskingContainer.clipsToBounds = true
        cardSurface.addSubview(cardContentMaskingContainer)

        cardContent.isAccessibilityElement = false
        cardContent.translatesAutoresizingMaskIntoConstraints = true
        cardContentMaskingContainer.addSubview(cardContent)

        miniatureContent.isAccessibilityElement = false
        miniatureContent.accessibilityElementsHidden = true
        miniatureContent.isUserInteractionEnabled = false
        cardSurface.addSubview(miniatureContent)
        NSLayoutConstraint.activate([
            miniatureContent.topAnchor.constraint(equalTo: cardSurface.topAnchor),
            miniatureContent.leadingAnchor.constraint(equalTo: cardSurface.leadingAnchor),
            miniatureContent.trailingAnchor.constraint(equalTo: cardSurface.trailingAnchor),
            miniatureContent.bottomAnchor.constraint(equalTo: cardSurface.bottomAnchor),
        ])

        miniatureTapButton.accessibilityLabel = lang("Expand")
        miniatureTapButton.isHidden = true
        miniatureTapButton.addTarget(self, action: #selector(expandFromMiniature), for: .touchUpInside)
        contentView.addSubview(miniatureTapButton)
    }

    func configure(
        headerViewModel: HomeHeaderViewModel,
        accountContext: AccountContext,
        layout: HomeCardLayoutMetrics = .screen,
        minimumHomeCardFontScale: CGFloat = 1
    ) {
        if observeToken != nil, container.headerViewModel === headerViewModel, container.accountContext === accountContext {
            applyLayoutMetrics(layout, minimumHomeCardFontScale: minimumHomeCardFontScale)
            return
        }
        HomeTrace.record("card.configure", "card=\(ObjectIdentifier(self)) state=\(headerViewModel.state)")
        observeToken?.cancel()
        observeToken = nil
        tintObservation?.cancel()
        tintObservation = observe { [weak self] in
            self?.contentView.tintColor = accountContext.accentColor
        }
        motionObservation?.cancel()
        interaction.setActive(false)
        self.container.headerViewModel = headerViewModel
        self.container.accountContext = accountContext
        cardBackground.configure(headerViewModel: headerViewModel, accountContext: accountContext)
        miniatureContent.configure(headerViewModel: headerViewModel, accountContext: accountContext)
        cardPromotion.configure(headerViewModel: headerViewModel, accountContext: accountContext)
        cardContent.configure(headerViewModel: headerViewModel, accountContext: accountContext)
        collapsedContent.configure(headerViewModel: headerViewModel, accountContext: accountContext)
        motionObservation = observe { [weak self] in
            guard let self else { return }
            let active = headerViewModel.allowsCardEffects(for: accountContext.account.id)
            let surface = CardSurfaceConfiguration.home(nft: accountContext.nft)
            // The finish belongs to every visible card, including neighbors and
            // incoming cells. Selection only gates live input, not its appearance.
            motionPreset = surface.motion
            cardContent.setMotionPreset(motionPreset)
            interaction.configure(surface: surface)
            interaction.setActive(active, animated: true)
            if !active { cardContent.setMotionLight(CardSurfaceLight(), preset: motionPreset) }
        }
        applyLayoutMetrics(layout, minimumHomeCardFontScale: minimumHomeCardFontScale, force: true)
        accessibilityObservation?.cancel()
        accessibilityObservation = observe { [weak self] in
            self?.updateAccessibilityState(headerViewModel: headerViewModel)
        }
        observeToken = observe { [weak self] in
            guard let self else { return }
            self.updateGeometryAndTransform(headerViewModel: headerViewModel)
        }
    }

    private func updateGeometryAndTransform(headerViewModel: HomeHeaderViewModel) {
        let stateChanged = appliedHeaderState != nil && appliedHeaderState != headerViewModel.state
        let now = CACurrentMediaTime()
        let wasAnimating = now < balanceAnimationDeadline
        let outgoing = appliedHeaderState == .collapsed ? collapsedContent : cardContent
        let outgoingLayer = outgoing.layer.presentation() ?? outgoing.layer
        let startFrame = outgoingLayer.convert(outgoing.balanceAlignmentFrame,
                                              to: contentView.layer.presentation() ?? contentView.layer)
        UIView.performWithoutAnimation {
            // Own both faces' geometry here so observer order cannot reset the
            // incoming face after its animation endpoints have been measured.
            cardContent.updateCollapseProgress(0)
            collapsedContent.updateCollapseProgress(headerViewModel.collapseProgress)
            if stateChanged || wasAnimating {
                cardContent.layer.removeAnimation(forKey: "transform")
                collapsedContent.layer.removeAnimation(forKey: "transform")
                alignBalances(to: startFrame)
            } else {
                applyTransform(headerViewModel: headerViewModel)
            }
        }
        appliedHeaderState = headerViewModel.state
        let startingTransforms = [cardContent.layer.transform, collapsedContent.layer.transform]
        if stateChanged {
            let isCollapsed = headerViewModel.isCollapsed
            let duration = isCollapsed ? 0.3 : (IOS_26_MODE_ENABLED ? 0.4 : 0.3)
            if #available(iOS 26.0, *) {
                balanceAnimationDeadline = now + duration + 0.105
            } else {
                balanceAnimationDeadline = now + duration
            }
            UIView.animateAdaptive(duration: duration) {
                self.applyTransform(headerViewModel: headerViewModel)
            }
            UIView.animate(withDuration: isCollapsed ? 0.25 : 0.05, delay: isCollapsed ? 0.1 : 0, options: isCollapsed ? [.curveEaseOut] : [.curveEaseIn]) {
                self.miniatureContent.alpha = isCollapsed ? 1 : 0
            }
        } else if wasAnimating {
            // Scrolling can continue during collapse. Retarget from the shared
            // presentation frame without extending the transition on each tick.
            UIView.animate(withDuration: balanceAnimationDeadline - now, delay: 0,
                           options: [.curveEaseOut, .allowUserInteraction]) {
                self.applyTransform(headerViewModel: headerViewModel)
            }
        }
        if stateChanged || wasAnimating {
            // Additive transform animations compose translations with each face's
            // different final scale. Absolute matrices preserve the common path.
            for (face, start) in zip([cardContent, collapsedContent], startingTransforms) {
                if let animation = face.layer.animation(forKey: "transform")?.copy() as? CABasicAnimation {
                    animation.isAdditive = false
                    animation.fromValue = NSValue(caTransform3D: start)
                    animation.toValue = NSValue(caTransform3D: face.layer.transform)
                    face.layer.add(animation, forKey: "transform")
                }
            }
        }
    }

    private func alignBalances(to target: CGRect) {
        let center = CGPoint(x: container.layout.itemWidth / 2, y: container.layout.itemHeight / 2)
        for face in [cardContent, collapsedContent] {
            let frame = face.balanceAlignmentFrame
            let scale = target.height / frame.height
            face.transform = CGAffineTransform(
                translationX: target.midX - center.x - (frame.midX - center.x) * scale,
                y: target.midY - center.y - (frame.midY - center.y) * scale
            ).scaledBy(x: scale, y: scale)
        }
    }

    private func applyTransform(headerViewModel: HomeHeaderViewModel) {
        let layout = container.layout
        guard layout.itemWidth > 0, layout.itemHeight > 0 else { return }
        let usesNavigationBarTopTabs = headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs
        let miniatureCardWidth: CGFloat = usesNavigationBarTopTabs ? 40.5 : 34
        // background
        let ofs: CGFloat =
            layout.itemHeight/2 -
            miniatureCardWidth/2*CARD_RATIO +
            headerViewModel.miniatureCardVerticalOffset
        let scale: CGFloat = miniatureCardWidth/layout.itemWidth
        contentView.layoutIfNeeded()
        alignBalances(to: headerViewModel.isCollapsed ? collapsedContent.balanceAlignmentFrame : cardContent.balanceAlignmentFrame)

        switch headerViewModel.state {
        case .expanded:
            self.cardBackground.transform = .identity
            self.cardPromotion.transform = .identity
            self.cardContentClipTransform = .identity
            self.miniatureContent.transform = .identity
        case .collapsed:
            let t = CGAffineTransform.identity
                .translatedBy(x: 0, y: ofs)
                .scaledBy(x: scale, y: scale)
            self.cardBackground.transform = t
            self.cardPromotion.transform = t
            self.cardContentClipTransform = t
            self.miniatureContent.transform = t
        }
        updateCardContentClip(layout)
        updateMiniatureTapButtonFrame()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        appliedHeaderState = nil
        balanceAnimationDeadline = 0
        motionObservation?.cancel()
        motionObservation = nil
        interaction.setActive(false)
        cardBackground.prepareForReuse()
        miniatureContent.prepareForReuse()
        cardPromotion.prepareForReuse()
        cardContent.prepareForReuse()
        collapsedContent.prepareForReuse()
        observeToken?.cancel()
        observeToken = nil
        tintObservation?.cancel()
        tintObservation = nil
        accessibilityObservation?.cancel()
        accessibilityObservation = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        interaction.updateVisibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCardContentClip(container.layout)
        updateMiniatureTapButtonFrame()
    }

    private func updateLayout(_ layout: HomeCardLayoutMetrics) {
        widthConstraint.constant = layout.itemWidth
        heightConstraint.constant = layout.itemHeight
    }

    func updateLayoutMetrics(
        _ layout: HomeCardLayoutMetrics,
        minimumHomeCardFontScale: CGFloat
    ) {
        applyLayoutMetrics(layout, minimumHomeCardFontScale: minimumHomeCardFontScale)
    }

    private func applyLayoutMetrics(
        _ layout: HomeCardLayoutMetrics,
        minimumHomeCardFontScale: CGFloat,
        force: Bool = false
    ) {
        let didChange = force ||
            container.layout != layout ||
            container.minimumHomeCardFontScale != minimumHomeCardFontScale
        container.layout = layout
        container.minimumHomeCardFontScale = minimumHomeCardFontScale
        guard didChange else { return }
        cardContent.updateLayout(layout, minimumFontScale: minimumHomeCardFontScale)
        collapsedContent.updateLayout(layout, minimumFontScale: minimumHomeCardFontScale)
        updateLayout(layout)
        updateCardContentClip(layout)
        guard let headerViewModel = container.headerViewModel else { return }
        UIView.performWithoutAnimation {
            cardContent.updateCollapseProgress(0)
            collapsedContent.updateCollapseProgress(headerViewModel.collapseProgress)
            applyTransform(headerViewModel: headerViewModel)
            appliedHeaderState = headerViewModel.state
            balanceAnimationDeadline = 0
            miniatureContent.alpha = headerViewModel.isCollapsed ? 1 : 0
            contentView.layoutIfNeeded()
        }
    }

    private func updateCardContentClip(_ layout: HomeCardLayoutMetrics) {
        let t = cardContentClipTransform
        let size = CGSize(width: layout.itemWidth * t.a, height: layout.itemHeight * t.d)
        cardContentMaskingContainer.bounds = CGRect(origin: .zero, size: size)
        cardContentMaskingContainer.center = CGPoint(x: layout.itemWidth / 2 + t.tx, y: layout.itemHeight / 2 + t.ty)
        cardContentMaskingContainer.layer.cornerRadius = 26 * t.a
        // Move the clip independently while the content keeps its original animation coordinates.
        cardContent.bounds = CGRect(x: 0, y: 0, width: layout.itemWidth, height: layout.itemHeight)
        cardContent.center = CGPoint(x: size.width / 2 - t.tx, y: size.height / 2 - t.ty)
    }

    private func updateMiniatureTapButtonFrame() {
        let miniatureFrame = miniatureContent.convert(miniatureContent.bounds, to: contentView)
        miniatureTapButton.bounds.size = CGSize(
            width: max(44, miniatureFrame.width),
            height: max(44, miniatureFrame.height)
        )
        miniatureTapButton.center = CGPoint(x: miniatureFrame.midX, y: miniatureFrame.midY)
    }

    @objc private func expandFromMiniature() {
        container.headerViewModel?.onExpand()
    }

    private func updateAccessibilityState(headerViewModel: HomeHeaderViewModel) {
        let isCollapsed = headerViewModel.isCollapsed
        let isHidden = headerViewModel.isCardHidden
        cardPresentation.isUserInteractionEnabled = !isCollapsed && !isHidden
        cardContentMaskingContainer.isUserInteractionEnabled = !isCollapsed && !isHidden
        collapsedContent.isUserInteractionEnabled = isCollapsed
        miniatureTapButton.isHidden = !isCollapsed || isHidden
        cardContent.accessibilityElementsHidden = isCollapsed || isHidden
        collapsedContent.accessibilityElementsHidden = !isCollapsed
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview(traits: .sizeThatFitsLayout) {
    let accountSource = AccountSource("0-mainnet")
    let headerViewModel = HomeHeaderViewModel(accountSource: accountSource)
    let accountContext = AccountContext(source: accountSource)
    let cell = HomeCard()
//    let _ = cell.contentView.layer.borderColor = UIColor.red.cgColor
    let _ = cell.contentView.layer.borderWidth = 1
    let _ = cell.configure(headerViewModel: headerViewModel, accountContext: accountContext)
    let _ = cell.heightAnchor.constraint(equalToConstant: HomeCardLayoutMetrics.screen.itemHeight).isActive = true
    let _ = cell.widthAnchor.constraint(equalToConstant: HomeCardLayoutMetrics.screen.itemWidth).isActive = true
    cell
//    let _ = DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//        headerViewModel.state = .collapsed
//    }
//    let _ = DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
//        headerViewModel.state = .expanded
//    }
//    let _ = DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
//        headerViewModel.state = .collapsed
//    }
}
#endif
