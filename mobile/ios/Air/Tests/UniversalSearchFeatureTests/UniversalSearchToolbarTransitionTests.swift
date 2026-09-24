import Testing
import UIComponents
import UIKit
import UIUniversalSearch
import WalletResources

@MainActor
@Suite("Universal Search toolbar transitions", .serialized)
struct UniversalSearchToolbarTransitionTests {
    private let tradeActions: [SharedBottomToolbarAction] = [
        .init(id: "buy", title: "Buy", style: .positive),
        .init(id: "sell", title: "Sell", style: .negative),
    ]

    @Test(arguments: [false, true])
    func `actions slide in when the toolbar stays compact`(isRTL: Bool) throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL)
        defer { window.isHidden = true }
        let transition = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: tradeActions))
        let buttons = actionButtons(in: toolbar)
        #expect(buttons.count == 2)
        for button in buttons {
            let frame = button.convert(button.bounds, to: toolbar)
            #expect(frame.width > 0)
            #expect(isRTL ? frame.maxX <= 0 : frame.minX >= toolbar.bounds.width)
        }

        toolbar.applyPreparedPresentationTransition(transition)
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: false)

        #expect(toolbar.presentation == .compactToolbar)
        #expect(toolbar.compactActions == tradeActions)
        expectVisibleActions(in: toolbar)
    }

    @Test(arguments: [false, true])
    func `pop retains outgoing actions until completion and restores them on cancellation`(isCancelled: Bool) throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setCompactActions(tradeActions)
        let buttons = actionButtons(in: toolbar)
        let frames = buttons.map { $0.convert($0.bounds, to: toolbar) }

        let transition = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: [], navigationOperation: .pop))
        #expect(buttons.map { $0.convert($0.bounds, to: toolbar) } == frames)
        #expect(buttons.allSatisfy { $0.superview != nil && !$0.isHidden })

        toolbar.applyPreparedPresentationTransition(transition)
        #expect(buttons.allSatisfy { $0.convert($0.bounds, to: toolbar).minX >= toolbar.bounds.width })
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: isCancelled)

        #expect(buttons.allSatisfy { $0.superview == nil })
        #expect(toolbar.compactActions == (isCancelled ? tradeActions : []))
        if isCancelled {
            expectVisibleActions(in: toolbar)
        } else {
            #expect(actionButtons(in: toolbar).isEmpty)
        }
    }

    @Test
    func `canceling a push removes incoming actions`() throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        let transition = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: tradeActions))
        toolbar.applyPreparedPresentationTransition(transition)
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: true)

        #expect(toolbar.presentation == .compactToolbar)
        #expect(toolbar.compactActions.isEmpty)
        #expect(actionButtons(in: toolbar).isEmpty)
    }

    @Test(arguments: [false, true])
    func `home to token transition restores the correct toolbar and actions`(isCancelled: Bool) throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setPresentation(.homeToolbar, animated: false)
        let transition = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: tradeActions))
        #expect(actionButtons(in: toolbar).allSatisfy {
            $0.convert($0.bounds, to: toolbar).minX >= toolbar.bounds.width
        })
        toolbar.applyPreparedPresentationTransition(transition)
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: isCancelled)

        #expect(toolbar.presentation == (isCancelled ? .homeToolbar : .compactToolbar))
        #expect(toolbar.compactActions == (isCancelled ? [] : tradeActions))
        if !isCancelled {
            expectVisibleActions(in: toolbar)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func `replacement actions follow push and pop direction`(isPop: Bool, isRTL: Bool) throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL)
        defer { window.isHidden = true }
        toolbar.setCompactActions(tradeActions)
        let outgoing = actionButtons(in: toolbar)
        let buyAction = [tradeActions[0]]
        let transition = try #require(toolbar.preparePresentationTransition(
            to: .compactToolbar,
            compactActions: buyAction,
            navigationOperation: isPop ? .pop : .push
        ))
        let incoming = actionButtons(in: toolbar).filter { button in
            !outgoing.contains(where: { $0 === button })
        }
        #expect(incoming.count == 1)
        let entersFromLeft = isPop != isRTL
        for button in incoming {
            let frame = button.convert(button.bounds, to: toolbar)
            #expect(entersFromLeft ? frame.maxX <= 0 : frame.minX >= toolbar.bounds.width)
        }

        toolbar.applyPreparedPresentationTransition(transition)
        for button in outgoing {
            let frame = button.convert(button.bounds, to: toolbar)
            #expect(entersFromLeft ? frame.minX >= toolbar.bounds.width : frame.maxX <= 0)
        }
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: false)
        #expect(outgoing.allSatisfy { $0.superview == nil })
        #expect(toolbar.compactActions == buyAction)
        #expect(incoming.allSatisfy { toolbar.bounds.contains($0.convert($0.bounds, to: toolbar)) })
    }

    @Test(arguments: [false, true])
    func `superseded callbacks cannot apply or finish a newer transition`(isCancelled: Bool) throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        let oldTransition = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: tradeActions))
        toolbar.applyPreparedPresentationTransition(oldTransition)
        let newActions = [tradeActions[0]]
        let newTransition = try #require(toolbar.preparePresentationTransition(to: .search, compactActions: newActions))
        let buttons = actionButtons(in: toolbar)

        #expect(!toolbar.applyPreparedPresentationTransition(oldTransition))
        #expect(!toolbar.finishPreparedPresentationTransition(oldTransition, isCancelled: isCancelled))
        #expect(toolbar.presentation == .compactToolbar)
        #expect(toolbar.compactActions == newActions)
        #expect(actionButtons(in: toolbar) == buttons)

        #expect(toolbar.applyPreparedPresentationTransition(newTransition))
        #expect(toolbar.finishPreparedPresentationTransition(newTransition, isCancelled: false))
        #expect(!toolbar.finishPreparedPresentationTransition(oldTransition, isCancelled: isCancelled))
        #expect(toolbar.presentation == .search)
        #expect(toolbar.compactActions == newActions)
    }

    @Test
    func `superseded property animator completion leaves the current transition intact`() throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear)
        toolbar.setPresentation(.search, animator: animator)
        animator.startAnimation()
        animator.stopAnimation(false)
        let transition = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: tradeActions))
        toolbar.applyPreparedPresentationTransition(transition)

        animator.finishAnimation(at: .start)
        #expect(toolbar.presentation == .compactToolbar)
        #expect(toolbar.compactActions == tradeActions)
        #expect(toolbar.finishPreparedPresentationTransition(transition, isCancelled: false))
        expectVisibleActions(in: toolbar)
    }

    private func makeToolbar(isRTL: Bool = false) -> (UIWindow, UniversalSearchFieldView) {
        _ = WalletResourcesBundle.bundle.load()
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 28),
            toolbar.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -28),
            toolbar.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -32),
            toolbar.heightAnchor.constraint(equalToConstant: 48),
        ])
        window.isHidden = false
        window.layoutIfNeeded()
        toolbar.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        toolbar.setPresentation(.compactToolbar, animated: false)
        return (window, toolbar)
    }

    private func actionButtons(in view: UIView) -> [UIControl] {
        if let control = view as? UIControl, ["Buy", "Sell"].contains(control.accessibilityLabel) {
            return [control]
        }
        return view.subviews.flatMap { actionButtons(in: $0) }
    }

    private func expectVisibleActions(in toolbar: UniversalSearchFieldView) {
        let buttons = actionButtons(in: toolbar)
        #expect(buttons.count == tradeActions.count)
        for button in buttons {
            let frame = button.convert(button.bounds, to: toolbar)
            #expect(toolbar.bounds.contains(frame))
            #expect(frame.width > 0)
            #expect(!button.isHidden && button.isUserInteractionEnabled)
        }
    }
}
