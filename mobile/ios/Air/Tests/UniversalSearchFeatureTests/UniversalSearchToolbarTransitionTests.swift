import Testing
import UIComponents
import UIKit
import UIUniversalSearch
import WalletResources

@MainActor
@Suite("Universal Search toolbar transitions", .serialized)
struct UniversalSearchToolbarTransitionTests {
    @Test
    func `compact action tint updates do not inherit surrounding animations`() async throws {
        guard #available(iOS 26, *) else { return }
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setCompactActions([.init(id: "buy", title: "Buy", style: .accent)])
        let button = try #require(actionButtons(in: toolbar).first)
        let material = try #require(effectViews(in: button).first)
        button.tintColor = .red
        try await Task.sleep(for: .milliseconds(300))
        let previousAnimations = animations(in: material.layer, excluding: material.contentView.layer)

        UIView.animate(withDuration: 1) {
            button.tintColor = .blue
        }
        let currentAnimations = animations(in: material.layer, excluding: material.contentView.layer)
        #expect(currentAnimations == previousAnimations, "Regular action materials must keep their immediate tint updates")
    }

    @Test(arguments: [UniversalSearchFieldPresentation.homeToolbar, .compactToolbar, .sideToolbar, .search])
    func `standard appearance refreshes leave regular controls untouched`(presentation: UniversalSearchFieldPresentation) async throws {
        guard #available(iOS 26, *) else { return }
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setPresentation(presentation, animated: false)
        try await Task.sleep(for: .milliseconds(300))
        let previousAnimations = animations(in: toolbar.layer)

        for _ in 0..<3 {
            toolbar.setOverlayAppearance(search: .standard, actions: .standard, animated: true)
        }
        let currentAnimations = animations(in: toolbar.layer)
        #expect(currentAnimations == previousAnimations)
        #expect(toolbar.searchButtonPresentationSourceView.overrideUserInterfaceStyle == .unspecified)
        #expect(toolbar.trailingButtonView.overrideUserInterfaceStyle == .unspecified)
    }

    @Test
    func `changing action contrast leaves unchanged search control untouched`() async throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setPresentation(.sideToolbar, animated: false)
        let dark = ContentOverlayAppearance(usesClearGlass: true, foregroundColor: .white, userInterfaceStyle: .dark)
        toolbar.setOverlayAppearance(search: dark, actions: dark, animated: false)
        try await Task.sleep(for: .milliseconds(300))
        let light = ContentOverlayAppearance(usesClearGlass: true, foregroundColor: .black, userInterfaceStyle: .light)
        let previousSearchAnimations = animations(in: toolbar.searchButtonPresentationSourceView.layer)

        toolbar.setOverlayAppearance(search: dark, actions: light, animated: true)
        let currentSearchAnimations = animations(in: toolbar.searchButtonPresentationSourceView.layer)
        #expect(currentSearchAnimations == previousSearchAnimations)
        #expect(!animations(in: toolbar.trailingButtonPresentationSourceView.layer).isEmpty)
    }

    private func animations(in layer: CALayer, excluding excludedLayer: CALayer? = nil) -> [ObjectIdentifier: [String]] {
        guard layer !== excludedLayer else { return [:] }
        var result: [ObjectIdentifier: [String]] = [:]
        if let keys = layer.animationKeys(), !keys.isEmpty { result[ObjectIdentifier(layer)] = keys }
        for child in layer.sublayers ?? [] {
            result.merge(animations(in: child, excluding: excludedLayer)) { _, new in new }
        }
        return result
    }

    private func effectViews(in view: UIView) -> [UIVisualEffectView] {
        (view as? UIVisualEffectView).map { [$0] } ?? view.subviews.flatMap { effectViews(in: $0) }
    }

    @Test
    func `content appearance restores semantic colors and material after search opens`() async throws {
        guard #available(iOS 26, *) else { return }
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        window.overrideUserInterfaceStyle = .light
        toolbar.setPresentation(.sideToolbar, animated: false)
        let dark = ContentOverlayAppearance(usesClearGlass: true, foregroundColor: .white, userInterfaceStyle: .dark)
        toolbar.setOverlayAppearance(search: dark, actions: dark, animated: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(toolbar.trailingButtonView.traitCollection.userInterfaceStyle == .dark)
        #expect(toolbar.searchButtonPresentationSourceView.traitCollection.userInterfaceStyle == .dark)
        let materials = glassEffects(in: toolbar)
        #expect(materials.count == 2)
        #expect(materials.allSatisfy { $0.isInteractive })

        toolbar.setPresentation(.search, animated: true)
        toolbar.setOverlayAppearance(search: .standard, actions: .standard, animated: true)
        try await Task.sleep(for: .milliseconds(350))
        #expect(toolbar.trailingButtonView.traitCollection.userInterfaceStyle == .light)
        #expect(toolbar.searchButtonPresentationSourceView.traitCollection.userInterfaceStyle == .light)
        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        #expect(toolbar.searchButtonPresentationSourceView.traitCollection.userInterfaceStyle == .dark,
                "Reset must resume inheriting the app theme")
        #expect(toolbar.trailingButtonView.overrideUserInterfaceStyle == .unspecified)
    }

    @available(iOS 26, *)
    private func glassEffects(in view: UIView) -> [UIGlassEffect] {
        let own = (view as? UIVisualEffectView)?.effect as? UIGlassEffect
        return (own.map { [$0] } ?? []) + view.subviews.flatMap { glassEffects(in: $0) }
    }

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

    @Test(arguments: [false, true], [false, true])
    func `side controls restore after completed and cancelled search transitions`(isRTL: Bool, isCancelled: Bool) throws {
        _ = WalletResourcesBundle.bundle.load()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 900))
        let controller = UIViewController()
        window.rootViewController = controller
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
        toolbar.translatesAutoresizingMaskIntoConstraints = true
        controller.view.addSubview(toolbar)
        toolbar.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        toolbar.frame = CGRect(x: 420, y: 740, width: 48, height: 108)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        toolbar.setPresentation(.sideToolbar, animated: false)
        toolbar.layoutIfNeeded()
        let actionFrame = toolbar.trailingButtonView.convert(toolbar.trailingButtonView.bounds, to: toolbar)
        #expect(actionFrame == CGRect(x: 0, y: 60, width: 48, height: 48))
        #expect(toolbar.hitTest(CGPoint(x: 24, y: 84), with: nil) != nil)
        #expect(!toolbar.trailingButtonView.accessibilityElementsHidden)
        toolbar.configuration.text = "ton"
        toolbar.layoutIfNeeded()
        func textField(in view: UIView) -> UITextField? {
            (view as? UITextField) ?? view.subviews.lazy.compactMap { textField(in: $0) }.first
        }
        let fieldContent = try #require(textField(in: toolbar)?.superview)
        #expect(fieldContent.bounds.size == CGSize(width: 48, height: 48))

        let transition = try #require(toolbar.preparePresentationTransition(to: .search))
        toolbar.frame = CGRect(x: 8, y: 600, width: 380, height: 48)
        toolbar.applyPreparedPresentationTransition(transition)
        toolbar.layoutIfNeeded()
        #expect(toolbar.presentation == .search)
        #expect(toolbar.trailingButtonView.convert(toolbar.trailingButtonView.bounds, to: toolbar).minY == 0)
        #expect(toolbar.bounds.contains(toolbar.trailingButtonView.convert(toolbar.trailingButtonView.bounds, to: toolbar)))

        if isCancelled {
            toolbar.frame = CGRect(x: 420, y: 740, width: 48, height: 108)
            toolbar.finishPreparedPresentationTransition(transition, isCancelled: true)
        } else {
            toolbar.finishPreparedPresentationTransition(transition, isCancelled: false)
            let collapse = try #require(toolbar.preparePresentationTransition(to: .sideToolbar))
            toolbar.frame = CGRect(x: 420, y: 740, width: 48, height: 108)
            toolbar.applyPreparedPresentationTransition(collapse)
            toolbar.finishPreparedPresentationTransition(collapse, isCancelled: false)
        }
        toolbar.layoutIfNeeded()
        #expect(toolbar.presentation == .sideToolbar)
        #expect(toolbar.text == "ton")
        #expect(toolbar.trailingButtonView.convert(toolbar.trailingButtonView.bounds, to: toolbar) == actionFrame)
        #expect(fieldContent.bounds.size == CGSize(width: 48, height: 48))
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
