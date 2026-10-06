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

    @Test
    func `editing changes follow focus transfers to and from another field`() {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        window.makeKeyAndVisible()
        toolbar.setPresentation(.search, animated: false)
        let otherField = UITextField(frame: CGRect(x: 20, y: 100, width: 200, height: 44))
        window.rootViewController?.view.addSubview(otherField)
        var editingChanges: [Bool] = []
        toolbar.onEditingChange = { editingChanges.append($0) }

        #expect(toolbar.focus())
        #expect(toolbar.isEditing)
        #expect(editingChanges == [true])

        #expect(otherField.becomeFirstResponder())
        #expect(!toolbar.isEditing)
        #expect(editingChanges == [true, false])

        #expect(toolbar.focus())
        #expect(toolbar.isEditing)
        #expect(editingChanges == [true, false, true])

        #expect(toolbar.endEditing())
        #expect(!toolbar.isEditing)
        #expect(editingChanges == [true, false, true, false])
    }

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

    @Test(arguments: [UniversalSearchFieldPresentation.homeToolbar, .search, .empty], [false, true])
    func `actions retrace their outgoing path when returning to a compact toolbar`(
        hiddenPresentation: UniversalSearchFieldPresentation,
        isRTL: Bool
    ) throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL)
        defer { window.isHidden = true }
        toolbar.setCompactActions(tradeActions)

        let push = try #require(toolbar.preparePresentationTransition(to: hiddenPresentation))
        toolbar.applyPreparedPresentationTransition(push)
        let outgoingFrames = actionFrames(in: toolbar, relativeTo: window)
        toolbar.finishPreparedPresentationTransition(push, isCancelled: false)
        // The navigation host releases actions once their provider leaves the screen.
        toolbar.setCompactActions([])

        for isCancelled in [true, false] {
            let pop = try #require(toolbar.preparePresentationTransition(
                to: .compactToolbar,
                compactActions: tradeActions,
                navigationOperation: .pop
            ))
            #expect(actionFrames(in: toolbar, relativeTo: window) == outgoingFrames)
            toolbar.applyPreparedPresentationTransition(pop)
            toolbar.finishPreparedPresentationTransition(pop, isCancelled: isCancelled)
            if isCancelled {
                #expect(toolbar.presentation == hiddenPresentation)
                #expect(actionButtons(in: toolbar).isEmpty)
            } else {
                expectVisibleActions(in: toolbar)
            }
        }
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

    @Test(arguments: [CGFloat(402), 845, 1400], [false, true])
    func `incoming and outgoing actions sit just beyond the visible panel`(panelWidth: CGFloat, isRTL: Bool) throws {
        for isPop in [false, true] {
            let (window, toolbar) = makeToolbar(isRTL: isRTL, panelWidth: panelWidth)
            defer { window.isHidden = true }
            toolbar.setCompactActions(tradeActions)
            let outgoing = actionButtons(in: toolbar)
            let transition = try #require(toolbar.preparePresentationTransition(
                to: .compactToolbar,
                compactActions: [tradeActions[0]],
                navigationOperation: isPop ? .pop : .push
            ))
            let incoming = actionButtons(in: toolbar).filter { !outgoing.contains($0) }
            let viewport = try #require(toolbar.transitionViewportView)
            let entersFromLeft = isPop != isRTL
            expectJustOutside(incoming, viewport: viewport, left: entersFromLeft)

            toolbar.applyPreparedPresentationTransition(transition)
            expectJustOutside(outgoing, viewport: viewport, left: !entersFromLeft)
            toolbar.finishPreparedPresentationTransition(transition, isCancelled: true)
            expectVisibleActions(in: toolbar)
        }
    }

    @Test(arguments: [CGFloat(402), 845, 1400], [false, true])
    func `hidden search clears the panel and returns in place on cancellation`(panelWidth: CGFloat, isRTL: Bool) throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL, panelWidth: panelWidth)
        defer { window.isHidden = true }
        toolbar.configuration.text = "gram"
        toolbar.setPresentation(.search, animated: false)
        let viewport = try #require(toolbar.transitionViewportView)
        let visibleFrame = toolbar.convert(toolbar.bounds, to: viewport)
        let transition = try #require(toolbar.preparePresentationTransition(to: .empty))
        toolbar.applyPreparedPresentationTransition(transition)
        expectJustOutside([toolbar], viewport: viewport, left: !isRTL)
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: true)
        #expect(toolbar.convert(toolbar.bounds, to: viewport) == visibleFrame)
        #expect(toolbar.text == "gram")

        toolbar.setPresentation(.empty, animated: false)
        for _ in 0..<3 {
            toolbar.setNeedsLayout()
            toolbar.layoutIfNeeded()
            expectJustOutside([toolbar], viewport: viewport, left: !isRTL)
        }
        window.frame.size.width += 500
        window.setNeedsLayout()
        window.layoutIfNeeded()
        expectJustOutside([toolbar], viewport: viewport, left: !isRTL)
        toolbar.setPresentation(.search, animated: false)
        #expect(viewport.bounds.contains(toolbar.convert(toolbar.bounds, to: viewport)))
    }

    private func expectJustOutside(_ controls: [UIView], viewport: UIView, left: Bool) {
        let frame = controls.reduce(CGRect.null) { $0.union($1.convert($1.bounds, to: viewport)) }
        #expect(!frame.isNull)
        let clearance = left ? viewport.bounds.minX - frame.maxX : frame.minX - viewport.bounds.maxX
        // Enough room for the glass shadow, with no device-sized extra travel.
        #expect(clearance >= 31.5 && clearance <= 32.5)
    }

    private func makeToolbar(isRTL: Bool = false, panelWidth: CGFloat = 402) -> (UIWindow, UniversalSearchFieldView) {
        _ = WalletResourcesBundle.bundle.load()
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
        let sidebarWidth: CGFloat = panelWidth > 402 ? 334 : 0
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: panelWidth + sidebarWidth, height: 874))
        let controller = UIViewController()
        window.rootViewController = controller
        let viewport = UIView()
        viewport.translatesAutoresizingMaskIntoConstraints = false
        viewport.clipsToBounds = true
        controller.view.addSubview(viewport)
        viewport.addSubview(toolbar)
        toolbar.transitionViewportView = viewport
        let width = toolbar.widthAnchor.constraint(equalTo: viewport.widthAnchor, constant: -56)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            viewport.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: sidebarWidth),
            viewport.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            viewport.topAnchor.constraint(equalTo: controller.view.topAnchor),
            viewport.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            toolbar.centerXAnchor.constraint(equalTo: viewport.centerXAnchor),
            width,
            toolbar.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            toolbar.bottomAnchor.constraint(equalTo: viewport.bottomAnchor, constant: -32),
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

    private func actionFrames(in toolbar: UniversalSearchFieldView, relativeTo view: UIView) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: actionButtons(in: toolbar).map {
            ($0.accessibilityLabel!, $0.convert($0.bounds, to: view))
        })
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
