import SwiftUI
import Testing
import UIKit
import WalletResources
@testable import UIComponents

@MainActor
struct WAlertControllerTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test
    func disabledAndNonDismissingActionsCanBeReplaced() throws {
        var calls = 0
        let alert = WAlertController(title: "Tip", message: nil, actions: [
            WAlertAction(title: "Disabled", isEnabled: false) { calls += 1 },
            WAlertAction(title: "Update", dismissAutomatically: false) { calls += 1 },
        ])
        alert.loadViewIfNeeded()
        let buttons = descendants(of: alert.view, as: WAlertActionButton.self)
        #expect(buttons.count == 2)
        try activate(buttons[0], in: alert)
        #expect(calls == 0)
        try activate(buttons[1], in: alert)
        #expect(calls == 1)
        alert.setActions([WAlertAction(title: "Done", style: .primary)])
        let replacement = descendants(of: alert.view, as: WAlertActionButton.self)
        #expect(replacement.count == 1)
        #expect(replacement.first?.accessibilityLabel == "Done")
    }

    @Test
    func dragSelectsReleaseTargetAndCancelsOutsideOrDisabledActions() throws {
        var selected: [String] = []
        let alert = WAlertController(title: "Tip", message: nil, actions: [
            WAlertAction(title: "First", dismissAutomatically: false) { selected.append("First") },
            WAlertAction(title: "Disabled", isEnabled: false, dismissAutomatically: false) { selected.append("Disabled") },
            WAlertAction(title: "Last", dismissAutomatically: false) { selected.append("Last") },
        ])
        alert.loadViewIfNeeded()
        alert.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        alert.view.layoutIfNeeded()
        let buttons = descendants(of: alert.view, as: WAlertActionButton.self)
        #expect(buttons.count == 3)
        let centers = buttons.map { $0.convert(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: alert.view) }
        let originalLabelFrames = buttons.flatMap { descendants(of: $0, as: UILabel.self) }.map(\.frame)
        alert.trackAction(at: centers[0], state: .began)
        #expect(buttons[0].isHighlighted)
        alert.trackAction(at: centers[1], state: .changed)
        #expect(buttons.allSatisfy { !$0.isHighlighted })
        alert.trackAction(at: centers[2], state: .changed)
        #expect(buttons[2].isHighlighted)
        #expect(!buttons[0].isHighlighted)
        alert.view.layoutIfNeeded()
        #expect(buttons.flatMap { descendants(of: $0, as: UILabel.self) }.map(\.frame) == originalLabelFrames)
        alert.trackAction(at: centers[2], state: .ended)
        #expect(selected == ["Last"])
        #expect(buttons.allSatisfy { !$0.isHighlighted })

        for endPoint in [CGPoint.zero, centers[1]] {
            alert.trackAction(at: centers[0], state: .began)
            alert.trackAction(at: endPoint, state: .changed)
            alert.trackAction(at: endPoint, state: .ended)
        }
        alert.trackAction(at: centers[0], state: .began)
        alert.trackAction(at: centers[0], state: .cancelled)
        #expect(selected == ["Last"])
        #expect(buttons.allSatisfy { !$0.isHighlighted })
    }

    @Test(arguments: [CGSize(width: 320, height: 568), CGSize(width: 844, height: 390)], [false, true])
    func longContentScrollsWithinTheAvailableHeight(size: CGSize, usesUIKit: Bool) throws {
        let message = Array(repeating: "Long tip content must remain readable and its action reachable.", count: 50).joined(separator: "\n")
        let alert: WAlertController
        if usesUIKit {
            alert = WAlertController(title: "Tip", message: message, actions: [WAlertAction(title: "OK")])
        } else {
            alert = WAlertController(actions: [WAlertAction(title: "OK")]) { Text(message) }
        }
        alert.loadViewIfNeeded()
        alert.view.frame = CGRect(origin: .zero, size: size)
        alert.view.layoutIfNeeded()
        let scroll = try #require(descendants(of: alert.view, as: UIScrollView.self).first)
        #expect(scroll.bounds.height > 0)
        #expect(scroll.contentSize.height > scroll.bounds.height)
        let visibleFrame = scroll.convert(scroll.bounds, to: alert.view)
        #expect(alert.view.safeAreaLayoutGuide.layoutFrame.contains(visibleFrame))
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        let button = try #require(descendants(of: alert.view, as: WAlertActionButton.self).first)
        #expect(scroll.bounds.contains(button.convert(button.bounds, to: scroll)))
    }

    @Test
    func nativeTipPreservesMarkdownAndParagraphs() throws {
        let tip = TipView(title: "Preview", message: "Result **is not guaranteed**.\n\nRead the [details](https://mywallet.io).", usesMarkdown: true)
        let alert = WAlertController(actions: [], contentView: tip)
        alert.loadViewIfNeeded()
        #expect(alert.children.isEmpty)
        let message = try #require(descendants(of: tip, as: UITextView.self).first)
        let text = try #require(message.attributedText)
        #expect(text.string == "Result is not guaranteed.\n\nRead the details.")
        let emphasizedRange = (text.string as NSString).range(of: "is not guaranteed")
        let font = try #require(text.attribute(.font, at: emphasizedRange.location, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        let linkRange = (text.string as NSString).range(of: "details")
        #expect(text.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL == URL(string: "https://mywallet.io"))
        #expect(message.isSelectable)
        #expect(!message.isEditable)
        #expect(!message.isScrollEnabled)
    }

    @Test
    func entranceFadesTheSharedAncestorOfGlassTextAndActions() throws {
        let alert = WAlertController(title: "Tip", message: "Content", actions: [WAlertAction(title: "OK")])
        let context = AlertTransitionContext(alert: alert, presenting: true)
        let animator = try #require(alert.animationController(forPresented: alert, presenting: context.presenter, source: context.presenter))
        animator.animateTransition(using: context)

        let dim = try #require(alert.view.subviews.first as? UIControl)
        let container = try #require(alert.view.subviews.last)
        #expect(!(container is UIVisualEffectView))
        #expect(descendants(of: container, as: UITextView.self).count == 1)
        #expect(descendants(of: container, as: WAlertActionButton.self).count == 1)
        #expect(!descendants(of: container, as: UIVisualEffectView.self).isEmpty)
        for effect in descendants(of: container, as: UIVisualEffectView.self) {
            #expect(effect.alpha == 1)
        }
        for view in [dim, container] {
            let fade = try #require(view.layer.animation(forKey: "opacity") as? CABasicAnimation)
            #expect(fade.fromValue as? NSNumber == 0)
            #expect(fade.toValue as? NSNumber == 1)
            #expect(fade.duration == 0.2)
            let timing = try #require(fade.timingFunction)
            var point = [Float](repeating: 0, count: 2)
            timing.getControlPoint(at: 1, values: &point)
            #expect(point == [0, 0])
            timing.getControlPoint(at: 2, values: &point)
            #expect(point == [1, 1])
            #expect(view.layer.opacity == 1)
        }
    }

    @Test
    func dismissalFadesFromTheVisibleOpacity() throws {
        let alert = WAlertController(title: "Tip", message: "Content", actions: [WAlertAction(title: "OK")])
        let context = AlertTransitionContext(alert: alert, presenting: false)
        context.containerView.addSubview(alert.view)
        alert.view.frame = context.containerView.bounds
        alert.view.layoutIfNeeded()
        let dim = try #require(alert.view.subviews.first as? UIControl)
        let container = try #require(alert.view.subviews.last)
        dim.layer.opacity = 0.4
        container.layer.opacity = 0.6
        let animator = try #require(alert.animationController(forDismissed: alert))
        animator.animateTransition(using: context)

        for (view, opacity) in [(dim as UIView, Float(0.4)), (container, Float(0.6))] {
            let fade = try #require(view.layer.animation(forKey: "opacity") as? CABasicAnimation)
            #expect((fade.fromValue as? NSNumber)?.floatValue == opacity)
            #expect(fade.toValue as? NSNumber == 0)
            #expect(fade.duration == 0.2)
            #expect(view.layer.opacity == 0)
        }
    }

    private func descendants<T: UIView>(of view: UIView, as type: T.Type) -> [T] {
        view.subviews.flatMap { subview in
            ((subview as? T).map { [$0] } ?? []) + descendants(of: subview, as: type)
        }
    }

    // SwiftPM tests have no UIApplication to dispatch UIControl events.
    private func activate(_ button: UIControl, in alert: WAlertController) throws {
        let action = try #require(button.actions(forTarget: alert, forControlEvent: .touchUpInside)?.first)
        alert.perform(NSSelectorFromString(action), with: button)
    }
}

@MainActor
private final class AlertTransitionContext: NSObject, UIViewControllerContextTransitioning {
    let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    let presenter = UIViewController()
    private let alert: WAlertController
    private let presenting: Bool
    let isAnimated = true
    let isInteractive = false
    let transitionWasCancelled = false
    let presentationStyle: UIModalPresentationStyle = .custom
    let targetTransform = CGAffineTransform.identity

    init(alert: WAlertController, presenting: Bool) {
        self.alert = alert
        self.presenting = presenting
    }

    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
        (key == .to) == presenting ? alert : presenter
    }

    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        viewController(forKey: key == .to ? .to : .from)?.view
    }

    func initialFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
    func finalFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
    func updateInteractiveTransition(_ percentComplete: CGFloat) {}
    func finishInteractiveTransition() {}
    func cancelInteractiveTransition() {}
    func pauseInteractiveTransition() {}
    func completeTransition(_ didComplete: Bool) {}
}
