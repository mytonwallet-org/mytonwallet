import Testing
import UIKit
import WalletResources
@testable import UIComponents

@MainActor @Suite(.serialized)
struct StoriesPresentationTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func sourceUsesLiveGeometryAndRejectsOffscreenReusedOrDetachedCards() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        let card = UIView(frame: CGRect(x: 16, y: 120, width: 370, height: 270))
        let button = UIButton(frame: CGRect(x: 24, y: 194, width: 322, height: 52))
        container.addSubview(card)
        card.addSubview(button)
        var valid = true
        let source = StoriesPresentationSource(view: card, button: button) { valid }
        let anchor = try #require(source.resolve(in: container))
        #expect(anchor.frame == card.frame)
        #expect(anchor.buttonFrame == CGRect(x: 40, y: 314, width: 322, height: 52))
        card.frame.origin.y = 140
        #expect(source.resolve(in: container)?.frame.minY == 140)
        card.frame.origin.y = 1_000
        #expect(source.resolve(in: container) == nil)
        card.frame.origin.y = 120
        valid = false
        #expect(source.resolve(in: container) == nil)
        valid = true
        card.removeFromSuperview()
        #expect(source.resolve(in: container) == nil)
    }

    @Test func restorationDoesNotOverwriteAReusedCardsVisibility() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        let card = UIView(frame: CGRect(x: 16, y: 120, width: 370, height: 270))
        let button = UIButton(frame: CGRect(x: 24, y: 194, width: 322, height: 52))
        container.addSubview(card)
        card.addSubview(button)
        var valid = true
        let source = StoriesPresentationSource(view: card, button: button) { valid }
        let anchor = try #require(source.resolve(in: container))
        source.hide(anchor)
        #expect(card.isHidden)
        source.restore()
        #expect(!card.isHidden)
        source.hide(anchor)
        valid = false
        source.restore()
        #expect(card.isHidden)
    }

    @Test func sourceAnchorsDoNotRetainTheCardOrItsButton() {
        weak var weakCard: UIView?
        weak var weakButton: UIButton?
        let source: StoriesPresentationSource
        do {
            let card = UIView()
            let button = UIButton()
            weakCard = card
            weakButton = button
            source = StoriesPresentationSource(view: card, button: button)
        }
        #expect(weakCard == nil && weakButton == nil)
        #expect(source.resolve(in: UIView()) == nil)
    }

    @Test func draggingMovesTheLiveSheetWithoutStartingTheZoomAndCancellationRestoresIt() async throws {
        let controller = StoriesViewController(pages: [
            .init(id: "intro", title: "Title", body: "Body", buttonTitle: "Next"),
        ])
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let pan = StoryPanGesture()
        pan.phase = .began
        controller.perform(NSSelectorFromString("panned:"), with: pan)
        pan.distance = 100
        pan.phase = .changed
        controller.perform(NSSelectorFromString("panned:"), with: pan)
        #expect(controller.view.transform == CGAffineTransform(translationX: 0, y: 100))
        #expect(controller.view.alpha == 1)
        #expect(!controller.isBeingDismissed)
        #expect(controller.playback.pauseReasons.contains(.dismissal))
        pan.phase = .cancelled
        controller.perform(NSSelectorFromString("panned:"), with: pan)
        try await Task.sleep(for: .milliseconds(500))
        #expect(controller.view.transform == .identity)
        #expect(!controller.view.clipsToBounds)
        #expect(!controller.playback.pauseReasons.contains(.dismissal))
        #expect(controller.playback.index == 0)
    }

    @Test func actionRemainsLiveWhileLiftedAndReturnsToItsLayout() throws {
        let controller = StoriesViewController(pages: [
            .init(id: "intro", title: "Title", body: "Body", buttonTitle: "Next"),
        ])
        controller.loadViewIfNeeded()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        controller.view.frame = container.bounds
        container.addSubview(controller.view)
        controller.view.layoutIfNeeded()
        let button = controller.transitionActionButton
        let parent = button.superview
        let frame = button.convert(button.bounds, to: container)
        let restore = controller.liftTransitionAction(into: container)
        #expect(button.superview === container)
        #expect(button.frame == frame)
        #expect(!button.isHidden)
        restore()
        #expect(button.superview === parent)
        #expect(!button.translatesAutoresizingMaskIntoConstraints)
        #expect(!button.isHidden)
        #expect(button.convert(button.bounds, to: container) == frame)
    }

    @Test func cardSnapshotKeepsItsContentGeometryAcrossRepeatedPresentationsAndDismissals() {
        let originalSize = CGSize(width: 370, height: 270)
        let snapshot = UIView(frame: CGRect(origin: .zero, size: originalSize))
        let illustrationFrame = CGRect(x: 154.5, y: 0, width: 216, height: 211)
        let illustration = UIView(frame: illustrationFrame)
        illustration.autoresizingMask = [.flexibleLeftMargin, .flexibleHeight]
        snapshot.addSubview(illustration)
        let flight = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        flight.addSubview(snapshot)

        for _ in 0..<3 {
            for size in [CGSize(width: 355, height: 259.05), flight.bounds.size,
                         CGSize(width: 390, height: 640), originalSize] {
                StoriesTransition.setSnapshotSize(size, on: snapshot)
                snapshot.layoutIfNeeded()
                #expect(snapshot.bounds.size == originalSize)
                #expect(illustration.frame == illustrationFrame)
                #expect(abs(snapshot.frame.minX) < 0.0001)
                #expect(abs(snapshot.frame.minY) < 0.0001)
                #expect(abs(snapshot.frame.width - size.width) < 0.0001)
                #expect(abs(snapshot.frame.height - size.height) < 0.0001)
            }
            #expect(snapshot.transform == .identity)
            #expect(illustration.convert(illustration.bounds, to: flight) == illustrationFrame)
        }
    }

}

@MainActor private final class StoryPanGesture: UIPanGestureRecognizer {
    var phase: UIGestureRecognizer.State = .possible
    var distance: CGFloat = 0
    override var state: UIGestureRecognizer.State {
        get { phase }
        set { phase = newValue }
    }
    override func translation(in view: UIView?) -> CGPoint { CGPoint(x: 0, y: distance) }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}
