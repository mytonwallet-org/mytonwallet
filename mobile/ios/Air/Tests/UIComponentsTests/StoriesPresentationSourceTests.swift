import Testing
import UIKit
import WalletResources
@testable import UIComponents

@MainActor @Suite(.serialized)
struct StoriesPresentationSourceTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func hiddenSourceRemainsResolvableAndRestoresOnlyWhenRequested() throws {
        let (window, container, card, button) = makeSourceViews()
        defer { window.isHidden = true }
        let source = StoriesPresentationSource(view: card, button: button)
        let anchor = try #require(source.resolve(in: container))
        let snapshot = source.makeSnapshot(anchor)
        source.hide(anchor)
        #expect(card.isHidden)
        #expect(!button.isHidden)
        let hiddenAnchor = try #require(source.resolve(in: container))
        #expect(hiddenAnchor.frame == anchor.frame)
        #expect(hiddenAnchor.buttonFrame == anchor.buttonFrame)
        #expect(source.makeSnapshot(hiddenAnchor) === snapshot)
        #expect(card.isHidden)
        source.hide(hiddenAnchor)
        source.restore()
        #expect(!card.isHidden)
        source.restore()
        #expect(!card.isHidden)
    }

    @Test func cancelledDismissalKeepsSourceHiddenUntilStoriesDisappears() throws {
        let (window, container, card, button) = makeSourceViews()
        defer { window.isHidden = true }
        let controller = StoriesViewController(pages: [
            .init(id: "intro", title: "Title", body: "Body", buttonTitle: "Next"),
        ])
        controller.presentationSource = StoriesPresentationSource(view: card, button: button)
        controller.view.frame = container.bounds
        container.addSubview(controller.view)
        controller.view.layoutIfNeeded()
        controller.viewDidAppear(false)
        defer { controller.viewDidDisappear(false) }
        #expect(card.isHidden)
        controller.viewWillDisappear(true)
        controller.resumeAfterCancelledDismissal()
        controller.viewDidAppear(false)
        #expect(card.isHidden)
        #expect(controller.presentationSource?.resolve(in: container) != nil)
        controller.viewDidDisappear(false)
        #expect(!card.isHidden)
    }

    @Test func pressedSourceResetsOnlyAfterHidingAndStaysResetWhenPresentationIsCancelled() throws {
        let (window, container, card, button) = makeSourceViews()
        defer { window.isHidden = true }
        let restingFrame = card.frame
        var resetCount = 0
        let source = StoriesPresentationSource(view: card, button: button, prepareForPresentation: {
            card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            return {
                #expect(card.isHidden)
                resetCount += 1
                card.transform = .identity
            }
        })
        #expect(card.frame == restingFrame)
        let anchor = try #require(source.resolve(in: container))
        #expect(anchor.frame.width < restingFrame.width)
        #expect(resetCount == 0)
        source.hide(anchor)
        #expect(card.isHidden)
        #expect(card.frame == restingFrame)
        #expect(source.resolve(in: container)?.frame == restingFrame)
        source.hide(anchor)
        #expect(resetCount == 1)
        source.restore()
        #expect(!card.isHidden)
        #expect(card.frame == restingFrame)
    }

    @Test func unusedSourcesDoNotPrepareAndAbortedPresentationRestoresAppearance() throws {
        let (window, container, card, button) = makeSourceViews()
        defer { window.isHidden = true }
        var prepareCount = 0
        let source = StoriesPresentationSource(view: card, button: button, prepareForPresentation: {
            prepareCount += 1
            card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            return { card.transform = .identity }
        })
        #expect(prepareCount == 0)
        card.isHidden = true
        #expect(source.resolve(in: container) == nil)
        #expect(prepareCount == 0)
        card.isHidden = false
        _ = try #require(source.resolve(in: container))
        #expect(prepareCount == 1)
        source.restore()
        #expect(!card.isHidden)
        #expect(card.transform == .identity)
    }

    @Test func reusedSourceIsNotResolvedOrUnhiddenByTheOldPresentation() throws {
        let (window, container, card, button) = makeSourceViews()
        defer { window.isHidden = true }
        var valid = true
        let source = StoriesPresentationSource(view: card, button: button, isValid: { valid })
        source.hide(try #require(source.resolve(in: container)))
        valid = false
        #expect(source.resolve(in: container) == nil)
        source.restore()
        #expect(card.isHidden)
    }

    @Test func hiddenOffscreenSourceFallsBackAndCanBeRestoredForLaterReuse() throws {
        let (window, container, card, button) = makeSourceViews()
        defer { window.isHidden = true }
        let source = StoriesPresentationSource(view: card, button: button)
        source.hide(try #require(source.resolve(in: container)))
        card.frame.origin.y = container.bounds.maxY + 100
        #expect(source.resolve(in: container) == nil)
        source.restore()
        #expect(!card.isHidden)
        card.frame.origin.y = 100
        #expect(source.resolve(in: container) != nil)
    }

    @Test func sourceHiddenByItsOwnerCannotBecomeAPresentationAnchor() {
        let (window, container, card, button) = makeSourceViews()
        defer { window.isHidden = true }
        let source = StoriesPresentationSource(view: card, button: button)
        card.isHidden = true
        #expect(source.resolve(in: container) == nil)
        source.restore()
        #expect(card.isHidden)
    }

    @Test func glassButtonRoutesTouchesInsideItsInteractiveEffect() throws {
        let (window, _, card, oldButton) = makeSourceViews()
        defer { window.isHidden = true }
        let button = WInteractiveGlassButton(style: .secondary)
        button.frame = oldButton.frame
        oldButton.removeFromSuperview()
        button.setTitle("Next", for: .normal)
        button.configureInteractiveGlass(tintColor: .white.withAlphaComponent(0.5), foregroundColor: .black)
        card.addSubview(button)
        button.layoutIfNeeded()
        let glass = try #require(button.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        let hit = try #require(window.hitTest(button.convert(center, to: window), with: nil))
        #expect(hit !== button)
        #expect(hit === glass || hit.isDescendant(of: glass))
        #expect(button.glassContentView === glass.contentView)
        #expect(button.glassTitleLabel.isDescendant(of: glass.contentView))
        #expect(button.glassTitleLabel.text == "Next")
        if #available(iOS 26, *) {
            let effect = try #require(glass.effect as? UIGlassEffect)
            #expect(effect.isInteractive)
        }
    }

    private func makeSourceViews() -> (UIWindow, UIView, UIView, UIButton) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        let card = UIView(frame: CGRect(x: 16, y: 100, width: 370, height: 270))
        card.backgroundColor = .blue
        let button = UIButton(frame: CGRect(x: 24, y: 194, width: 322, height: 52))
        button.setTitle("Open", for: .normal)
        card.addSubview(button)
        container.addSubview(card)
        return (window, container, card, button)
    }
}
