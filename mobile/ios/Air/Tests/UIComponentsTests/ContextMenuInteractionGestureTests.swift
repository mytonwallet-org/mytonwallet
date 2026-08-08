import Testing
import UIKit
@testable import ContextMenuKit

@Suite("Context Menu Interaction Gestures")
@MainActor
struct ContextMenuInteractionGestureTests {
    @Test
    func `long press takes precedence over same view taps`() throws {
        let sourceView = UIView()
        let tapGestureRecognizer = UITapGestureRecognizer()
        sourceView.addGestureRecognizer(tapGestureRecognizer)
        let (interaction, longPressGestureRecognizer) = try makeInteraction(
            sourceView: sourceView,
            usesPressAnimation: true
        )

        #expect(interaction.gestureRecognizer(
            longPressGestureRecognizer,
            shouldBeRequiredToFailBy: tapGestureRecognizer
        ))
    }

    @Test(arguments: [false, true])
    func `long press takes precedence over descendant taps`(usesPressAnimation: Bool) throws {
        let sourceView = UIView()
        let tappedSubview = UIView()
        sourceView.addSubview(tappedSubview)
        let tapGestureRecognizer = UITapGestureRecognizer()
        tappedSubview.addGestureRecognizer(tapGestureRecognizer)
        let (interaction, longPressGestureRecognizer) = try makeInteraction(
            sourceView: sourceView,
            usesPressAnimation: usesPressAnimation
        )

        #expect(interaction.gestureRecognizer(
            longPressGestureRecognizer,
            shouldBeRequiredToFailBy: tapGestureRecognizer
        ))
    }

    @Test
    func `long press takes precedence over ancestor taps`() throws {
        let ancestorView = UIView()
        let sourceView = UIView()
        ancestorView.addSubview(sourceView)
        let tapGestureRecognizer = UITapGestureRecognizer()
        ancestorView.addGestureRecognizer(tapGestureRecognizer)
        let (interaction, longPressGestureRecognizer) = try makeInteraction(
            sourceView: sourceView,
            usesPressAnimation: true
        )

        #expect(interaction.gestureRecognizer(
            longPressGestureRecognizer,
            shouldBeRequiredToFailBy: tapGestureRecognizer
        ))
    }

    @Test
    func `long press does not take precedence over pans or unrelated taps`() throws {
        let sourceView = UIView()
        let sourceSubview = UIView()
        sourceView.addSubview(sourceSubview)
        let panGestureRecognizer = UIPanGestureRecognizer()
        sourceSubview.addGestureRecognizer(panGestureRecognizer)
        let unrelatedView = UIView()
        let unrelatedTapGestureRecognizer = UITapGestureRecognizer()
        unrelatedView.addGestureRecognizer(unrelatedTapGestureRecognizer)
        let (interaction, longPressGestureRecognizer) = try makeInteraction(
            sourceView: sourceView,
            usesPressAnimation: true
        )

        #expect(!interaction.gestureRecognizer(
            longPressGestureRecognizer,
            shouldBeRequiredToFailBy: panGestureRecognizer
        ))
        #expect(!interaction.gestureRecognizer(
            longPressGestureRecognizer,
            shouldBeRequiredToFailBy: unrelatedTapGestureRecognizer
        ))
    }

    @Test
    func `opening menu cancels active recognizer tracking source touch from ancestor`() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let sourceView = UIView(frame: CGRect(x: 20, y: 30, width: 100, height: 50))
        window.addSubview(sourceView)
        let activeGestureRecognizer = TestGestureRecognizer(location: CGPoint(x: 30, y: 25))
        sourceView.addGestureRecognizer(activeGestureRecognizer)
        let competingGestureRecognizer = TestGestureRecognizer(location: CGPoint(x: 50, y: 55))
        window.addGestureRecognizer(competingGestureRecognizer)
        competingGestureRecognizer.begin()
        let interaction = ContextMenuInteraction(triggers: []) { _ in nil }

        interaction.cancelCompetingGestureRecognizers(
            on: sourceView,
            excluding: activeGestureRecognizer
        )

        #expect(competingGestureRecognizer.enablementChanges == [false, true])
    }

    @Test
    func `opening menu leaves unrelated active ancestor recognizer running`() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let sourceView = UIView(frame: CGRect(x: 20, y: 30, width: 100, height: 50))
        window.addSubview(sourceView)
        let activeGestureRecognizer = TestGestureRecognizer(location: CGPoint(x: 30, y: 25))
        sourceView.addGestureRecognizer(activeGestureRecognizer)
        let unrelatedGestureRecognizer = TestGestureRecognizer(location: CGPoint(x: 250, y: 500))
        window.addGestureRecognizer(unrelatedGestureRecognizer)
        unrelatedGestureRecognizer.begin()
        let interaction = ContextMenuInteraction(triggers: []) { _ in nil }

        interaction.cancelCompetingGestureRecognizers(
            on: sourceView,
            excluding: activeGestureRecognizer
        )

        #expect(unrelatedGestureRecognizer.enablementChanges.isEmpty)
    }

    private func makeInteraction(
        sourceView: UIView,
        usesPressAnimation: Bool
    ) throws -> (ContextMenuInteraction, UIGestureRecognizer) {
        let interaction = ContextMenuInteraction(
            triggers: [.longPress],
            pressAnimation: usesPressAnimation ? .default() : nil,
            configurationProvider: { _ in nil }
        )
        interaction.attach(to: sourceView)
        let longPressGestureRecognizer = try #require(
            sourceView.gestureRecognizers?.first { !($0 is UITapGestureRecognizer) }
        )
        return (interaction, longPressGestureRecognizer)
    }
}

@MainActor
private final class TestGestureRecognizer: UIGestureRecognizer {
    private let testLocation: CGPoint
    private var reportedState: UIGestureRecognizer.State = .possible
    private(set) var enablementChanges: [Bool] = []

    init(location: CGPoint) {
        self.testLocation = location
        super.init(target: nil, action: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet {
            enablementChanges.append(isEnabled)
        }
    }

    override var state: UIGestureRecognizer.State {
        get {
            reportedState
        }
        set {
            reportedState = newValue
        }
    }

    override func location(in view: UIView?) -> CGPoint {
        guard let recognizerView = self.view, let view else {
            return testLocation
        }
        return recognizerView.convert(testLocation, to: view)
    }

    func begin() {
        reportedState = .began
    }
}
