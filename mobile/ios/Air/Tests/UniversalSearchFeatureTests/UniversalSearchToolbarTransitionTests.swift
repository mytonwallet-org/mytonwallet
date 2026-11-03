import Testing
import UIComponents
import UIKit
import UIUniversalSearch
import WalletContext
import WalletResources

@MainActor
@Suite("Universal Search toolbar transitions", .serialized)
struct UniversalSearchToolbarTransitionTests {
    @Test(arguments: [false, true], [CGFloat(375), CGFloat(700)])
    func `compact search receives taps with every home button configuration`(isRTL: Bool, panelWidth: CGFloat) throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL, panelWidth: panelWidth)
        defer { window.isHidden = true }
        for shared in [false, true] {
            for accounts in [false, true] {
                for scan in [false, true] {
                    toolbar.setHomeConfiguration(.init(showsAccounts: accounts, showsScan: scan, sharesBackground: shared), animated: false)
                    for actions in [[], tradeActions] {
                        toolbar.setCompactActions(actions)
                        toolbar.layoutIfNeeded()
                        try expectTapReaches(toolbar.searchButtonPresentationSourceView, in: window)
                    }
                }
            }
        }
    }

    @Test(arguments: [false, true], [false, true])
    func `compact search and trailing controls restore hit testing after navigation`(shared: Bool, cancelled: Bool) throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: shared), animated: false)
        for target in [UniversalSearchFieldPresentation.search, .homeToolbar] {
            let transition = try #require(toolbar.preparePresentationTransition(to: target))
            toolbar.applyPreparedPresentationTransition(transition)
            toolbar.layoutIfNeeded()
            try expectTapReaches(toolbar.trailingButtonView, in: window)
            toolbar.finishPreparedPresentationTransition(transition, isCancelled: cancelled)
            if !cancelled {
                try expectTapReaches(toolbar.trailingButtonView, in: window)
                if target == .homeToolbar {
                    try expectTapReaches(toolbar.accountsButton, in: window)
                    try expectTapReaches(try #require(toolbar.scanButtonPresentationSourceView), in: window)
                }
                let collapse = try #require(toolbar.preparePresentationTransition(to: .compactToolbar))
                toolbar.applyPreparedPresentationTransition(collapse)
                toolbar.finishPreparedPresentationTransition(collapse, isCancelled: false)
            }
            toolbar.layoutIfNeeded()
            try expectTapReaches(toolbar.searchButtonPresentationSourceView, in: window)
        }
    }

    private func expectTapReaches(_ control: UIView, in window: UIWindow) throws {
        let point = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: window)
        let hit = try #require(window.hitTest(point, with: nil))
        #expect(hit === control || hit.isDescendant(of: control), "Tap on \(type(of: control)) was intercepted by \(type(of: hit))")
    }

    @Test(arguments: [false, true], [false, true])
    func `vertical toolbar lays out every optional button configuration`(shared: Bool, isRTL: Bool) throws {
        let (window, toolbar) = makeSideToolbar(isRTL: isRTL)
        defer { window.isHidden = true }
        for accounts in [false, true] {
            for scan in [false, true] {
                toolbar.setHomeConfiguration(.init(showsAccounts: accounts, showsScan: scan, sharesBackground: shared), animated: false)
                toolbar.layoutIfNeeded()
                var controls = [toolbar.searchButtonPresentationSourceView]
                if accounts { controls.append(toolbar.accountsButton) }
                if scan { controls.append(try #require(toolbar.scanButtonPresentationSourceView)) }
                controls.append(toolbar.trailingButtonView)
                let frames = controls.map { $0.convert($0.bounds, to: toolbar) }
                #expect(toolbar.bounds.height == toolbar.sideToolbarHeight)
                #expect(frames.last?.maxY == toolbar.bounds.maxY)
                #expect(toolbar.accountsButton.isHidden == !accounts)
                #expect((toolbar.scanButtonPresentationSourceView != nil) == scan)
                for frame in frames {
                    #expect(frame.size == CGSize(width: 48, height: 48))
                    #expect(toolbar.bounds.contains(frame))
                }
                for index in 1..<frames.count {
                    #expect(frames[index].minY >= frames[index - 1].maxY)
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func `vertical glass merges and splits while the action button stays anchored`(isRTL: Bool) async throws {
        guard #available(iOS 26, *), IOS_26_MODE_ENABLED else { return }
        let (window, toolbar) = makeSideToolbar(isRTL: isRTL)
        defer { window.isHidden = true }
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: false), animated: false)
        let actionBottom = toolbar.trailingButtonView.convert(toolbar.trailingButtonView.bounds, to: window).maxY
        for shared in [true, false] {
            toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: shared), animated: true)
            let scan = try #require(toolbar.scanButtonPresentationSourceView)
            let controls = [toolbar.accountsButton, scan, toolbar.trailingButtonView]
            let groupFrame = controls.reduce(CGRect.null) { $0.union($1.convert($1.bounds, to: toolbar)) }
            let glass = transitionGlassViews(in: toolbar)
            #expect(glass.count == 3)
            for (background, control) in zip(glass, controls) {
                #expect(background.convert(background.bounds, to: toolbar) == (shared ? groupFrame : control.convert(control.bounds, to: toolbar)))
                #expect(background.alpha == 1)
            }
            #expect(toolbar.trailingButtonView.convert(toolbar.trailingButtonView.bounds, to: window).maxY == actionBottom)
            try await Task.sleep(for: .milliseconds(500))
            #expect(transitionGlassViews(in: toolbar).isEmpty)
        }
    }

    private func makeSideToolbar(isRTL: Bool) -> (UIWindow, UniversalSearchFieldView) {
        _ = WalletResourcesBundle.bundle.load()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 900))
        let root = UIViewController()
        window.rootViewController = root
        let toolbar = UniversalSearchFieldView(configuration: .init(placeholder: "Search"))
        toolbar.translatesAutoresizingMaskIntoConstraints = true
        root.view.addSubview(toolbar)
        forceLayoutDirection(in: toolbar, isRTL: isRTL)
        let updateFrame = { [weak toolbar] in
            guard let toolbar else { return }
            toolbar.frame = CGRect(x: 420, y: 868 - toolbar.sideToolbarHeight, width: 48, height: toolbar.sideToolbarHeight)
        }
        toolbar.onHomeConfigurationLayoutChange = updateFrame
        updateFrame()
        window.makeKeyAndVisible()
        toolbar.setPresentation(.sideToolbar, animated: false)
        toolbar.layoutIfNeeded()
        return (window, toolbar)
    }

    @Test(arguments: [false, true], [false, true])
    func `home placeholder follows space reserved by optional buttons`(shared: Bool, isRTL: Bool) throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL, panelWidth: 375)
        defer { window.isHidden = true }
        toolbar.configuration = .init(placeholder: "Искать или спросить", shortPlaceholder: "Поиск", showsMicrophone: false)
        toolbar.setHomeConfiguration(.init(showsAccounts: false, showsScan: false, sharesBackground: shared), animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        toolbar.layoutIfNeeded()
        let field = try #require(searchTextField(in: toolbar))
        #expect(field.attributedPlaceholder?.string == "Искать или спросить")

        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: shared), animated: false)
        toolbar.layoutIfNeeded()
        #expect(field.attributedPlaceholder?.string == "Поиск")
        #expect(toolbar.searchButtonPresentationSourceView.accessibilityLabel == "Поиск")

        toolbar.setHomeConfiguration(.init(showsAccounts: false, showsScan: false, sharesBackground: shared), animated: false)
        toolbar.layoutIfNeeded()
        #expect(field.attributedPlaceholder?.string == "Искать или спросить")
        #expect(toolbar.configuration.placeholder == "Искать или спросить")
    }

    @Test(arguments: [false, true])
    func `placeholder remeasures after resizing and cancelled search`(isRTL: Bool) throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL, panelWidth: 375)
        defer { window.isHidden = true }
        toolbar.configuration = .init(placeholder: "Search or Ask", shortPlaceholder: "Search", showsMicrophone: false)
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: false), animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        toolbar.layoutIfNeeded()
        let field = try #require(searchTextField(in: toolbar))
        #expect(field.attributedPlaceholder?.string == "Search")

        window.frame.size.width = 700
        window.layoutIfNeeded()
        #expect(field.attributedPlaceholder?.string == "Search or Ask")
        window.frame.size.width = 375
        window.layoutIfNeeded()
        #expect(field.attributedPlaceholder?.string == "Search")

        let transition = try #require(toolbar.preparePresentationTransition(to: .search))
        toolbar.applyPreparedPresentationTransition(transition)
        toolbar.layoutIfNeeded()
        #expect(field.attributedPlaceholder?.string == "Search or Ask")
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: true)
        toolbar.layoutIfNeeded()
        #expect(field.attributedPlaceholder?.string == "Search")
    }

    @Test
    func `a fixed placeholder remains unchanged when space is limited`() throws {
        let (window, toolbar) = makeToolbar(panelWidth: 320)
        defer { window.isHidden = true }
        toolbar.configuration = .init(placeholder: "Search", showsMicrophone: false)
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: false), animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        toolbar.layoutIfNeeded()
        #expect(searchTextField(in: toolbar)?.attributedPlaceholder?.string == "Search")
    }

    @Test(arguments: [UniversalSearchFieldPresentation.compactToolbar, .search], [false, true])
    func `placeholder crossfade follows interactive navigation in both directions`(
        source: UniversalSearchFieldPresentation, isRTL: Bool
    ) async throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL, panelWidth: 375)
        defer { window.isHidden = true }
        toolbar.configuration = .init(placeholder: "Search or Ask", shortPlaceholder: "Search", showsMicrophone: false)
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: false), animated: false)
        toolbar.setPresentation(source, animated: false)
        toolbar.layoutIfNeeded()
        let field = try #require(searchTextField(in: toolbar))
        let labels = field.subviews.flatMap(\.subviews).compactMap { $0 as? UILabel }
        let full = try #require(labels.first { $0.attributedText?.string == "Search or Ask" }?.superview)
        let short = try #require(labels.first { $0.attributedText?.string == "Search" }?.superview)
        try await Task.sleep(for: .milliseconds(50))

        for cancelled in [true, false] {
            let transition = try #require(toolbar.preparePresentationTransition(to: .homeToolbar, navigationOperation: .pop))
            let animator = UIViewPropertyAnimator(duration: 1, curve: .linear)
            animator.addAnimations {
                toolbar.applyPreparedPresentationTransition(transition)
                window.layoutIfNeeded()
            }
            animator.addCompletion { _ in
                toolbar.finishPreparedPresentationTransition(transition, isCancelled: cancelled)
            }
            animator.startAnimation()
            animator.pauseAnimation()

            // Moving backwards must restore the same intermediate appearance;
            // a separate timed crossfade cannot follow a cancelled swipe.
            for progress in [CGFloat(0.25), 0.75, 0.25] {
                animator.fractionComplete = progress
                try await Task.sleep(for: .milliseconds(50))
                let fullOpacity = try #require(full.layer.presentation()?.opacity)
                let shortOpacity = try #require(short.layer.presentation()?.opacity)
                let fieldOpacity = try #require(field.layer.presentation()?.opacity)
                #expect(abs(CGFloat(fullOpacity) - (1 - progress)) < 0.06)
                #expect(abs(CGFloat(shortOpacity) - progress) < 0.06)
                #expect(abs(CGFloat(fieldOpacity) - (source == .compactToolbar ? progress : 1)) < 0.06)
            }

            animator.stopAnimation(false)
            animator.finishAnimation(at: cancelled ? .start : .end)
            toolbar.layoutIfNeeded()
            #expect(field.attributedPlaceholder?.string == (cancelled ? "Search or Ask" : "Search"))
            #expect(full.alpha == (cancelled ? 1 : 0))
            #expect(short.alpha == (cancelled ? 0 : 1))
            #expect(field.alpha == (cancelled && source == .compactToolbar ? 0 : 1))
        }

        toolbar.configuration.text = "ton"
        #expect(full.isHidden && short.isHidden)
        toolbar.configuration.text = ""
        #expect(!full.isHidden && !short.isHidden)
    }

    private func searchTextField(in view: UIView) -> UITextField? {
        (view as? UITextField) ?? view.subviews.lazy.compactMap { searchTextField(in: $0) }.first
    }

    @Test(arguments: [false, true])
    func `shared background merges and splits live glass geometry`(isRTL: Bool) async throws {
        guard #available(iOS 26, *), IOS_26_MODE_ENABLED else { return }
        let (window, toolbar) = makeToolbar(isRTL: isRTL)
        defer { window.isHidden = true }
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: false), animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        let scan = try #require(toolbar.scanButtonPresentationSourceView)

        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: true), animated: true)
        let merged = transitionGlassViews(in: toolbar)
        #expect(merged.count == 3)
        let groupFrame = [toolbar.accountsButton, scan, toolbar.trailingButtonView].reduce(CGRect.null) {
            $0.union($1.convert($1.bounds, to: toolbar))
        }
        for glass in merged {
            #expect(glass.convert(glass.bounds, to: toolbar) == groupFrame)
            #expect(glass.effect is UIGlassEffect)
            #expect(glass.alpha == 1)
        }
        try await Task.sleep(for: .milliseconds(500))
        #expect(merged.allSatisfy { $0.superview == nil })
        #expect(glassEffects(in: toolbar).count == 2)
        #expect(glassEffects(in: toolbar).allSatisfy { $0.isInteractive })

        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: false), animated: true)
        let split = transitionGlassViews(in: toolbar)
        #expect(split.count == 3)
        for (glass, button) in zip(split, [toolbar.accountsButton, scan, toolbar.trailingButtonView]) {
            #expect(glass.convert(glass.bounds, to: toolbar) == button.convert(button.bounds, to: toolbar))
            #expect(glass.effect is UIGlassEffect)
            #expect(glass.alpha == 1)
        }
        try await Task.sleep(for: .milliseconds(500))
        #expect(split.allSatisfy { $0.superview == nil })
        #expect(glassEffects(in: toolbar).count == 4)
    }

    @Test
    func `removing optional buttons keeps their glass until it reaches the action button`() async throws {
        guard #available(iOS 26, *), IOS_26_MODE_ENABLED else { return }
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: false), animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        toolbar.setHomeConfiguration(.init(showsAccounts: false, showsScan: false, sharesBackground: false), animated: true)
        let backgrounds = transitionGlassViews(in: toolbar)
        #expect(backgrounds.count == 3)
        let finalFrame = toolbar.trailingButtonView.convert(toolbar.trailingButtonView.bounds, to: toolbar)
        for glass in backgrounds {
            #expect(glass.convert(glass.bounds, to: toolbar) == finalFrame)
            #expect(glass.effect is UIGlassEffect)
            #expect(glass.alpha == 1)
        }
        try await Task.sleep(for: .milliseconds(500))
        #expect(backgrounds.allSatisfy { $0.superview == nil })
        #expect(glassEffects(in: toolbar).count == 2)
    }

    private func transitionGlassViews(in view: UIView) -> [UIVisualEffectView] {
        effectViews(in: view).filter { $0.accessibilityIdentifier?.hasPrefix("home_toolbar_transition_glass_") == true }
    }

    @Test
    func `queued preferences still animate after cancelled navigation`() async throws {
        guard #available(iOS 26, *), IOS_26_MODE_ENABLED else { return }
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setPresentation(.homeToolbar, animated: false)
        let transition = try #require(toolbar.preparePresentationTransition(to: .search))
        toolbar.applyPreparedPresentationTransition(transition)
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: false, sharesBackground: false), animated: true)
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: true)
        #expect(transitionGlassViews(in: toolbar).count == 3)
        try await Task.sleep(for: .milliseconds(500))
        #expect(transitionGlassViews(in: toolbar).isEmpty)
        #expect(!toolbar.accountsButton.isHidden)
        #expect(toolbar.scanButtonPresentationSourceView == nil)
    }

    @Test
    func `navigation reuses its glass views`() throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: true), animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        var glassViews = Set<ObjectIdentifier>()
        func visitToken() throws {
            let push = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: tradeActions))
            glassViews.formUnion(effectViews(in: toolbar).map { ObjectIdentifier($0) })
            toolbar.applyPreparedPresentationTransition(push)
            toolbar.finishPreparedPresentationTransition(push, isCancelled: false)
            let pop = try #require(toolbar.preparePresentationTransition(to: .homeToolbar, navigationOperation: .pop))
            glassViews.formUnion(effectViews(in: toolbar).map { ObjectIdentifier($0) })
            toolbar.applyPreparedPresentationTransition(pop)
            toolbar.finishPreparedPresentationTransition(pop, isCancelled: false)
            // The navigation host releases actions once their provider leaves the screen.
            toolbar.setCompactActions([])
        }
        try visitToken()
        let firstVisit = glassViews
        for _ in 0..<10 {
            try visitToken()
        }
        #expect(glassViews == firstVisit)
    }

    @Test
    func `returning home renews a glass container that many glass views joined`() throws {
        guard #available(iOS 26, *), IOS_26_MODE_ENABLED else { return }
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setPresentation(.homeToolbar, animated: false)
        let container = try #require(toolbar.subviews.first as? UIVisualEffectView)
        let effect = try #require(container.effect as? UIGlassContainerEffect)
        let assignments = EffectAssignments()
        let observation = container.observe(\.effect, options: .new) { _, change in
            MainActor.assumeIsolated { assignments.effects.append(change.newValue ?? nil) }
        }
        defer { observation.invalidate() }
        // Hosted glass joins the container and leaves it during the push
        let hostedGlass = (0..<48).map { _ in UIVisualEffectView(effect: UIGlassEffect()) }
        hostedGlass.forEach { toolbar.glassContentView.addSubview($0) }
        let push = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: tradeActions))
        hostedGlass.forEach { $0.removeFromSuperview() }
        toolbar.applyPreparedPresentationTransition(push)
        toolbar.finishPreparedPresentationTransition(push, isCancelled: false)
        #expect(assignments.effects.isEmpty, "Tinted actions on screen keep the container's glass")

        let pop = try #require(toolbar.preparePresentationTransition(to: .homeToolbar, navigationOperation: .pop))
        toolbar.applyPreparedPresentationTransition(pop)
        toolbar.finishPreparedPresentationTransition(pop, isCancelled: false)
        #expect(assignments.effects.map { $0 == nil } == [true, false])
        #expect((container.effect as? UIGlassContainerEffect)?.spacing == effect.spacing)
    }

    @Test(arguments: [false, true], [false, true])
    func `home buttons reserve space in logical order and preserve touch targets`(shared: Bool, isRTL: Bool) throws {
        let (window, toolbar) = makeToolbar(isRTL: isRTL, panelWidth: 320)
        defer { window.isHidden = true }
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true, sharesBackground: shared), animated: false)
        toolbar.setPresentation(.homeToolbar, animated: false)
        let scan = try #require(toolbar.scanButtonPresentationSourceView)
        let accounts = toolbar.accountsButton
        let controls = [toolbar.searchButtonPresentationSourceView, accounts, scan, toolbar.trailingButtonView]
        let frames = controls.map { $0.convert($0.bounds, to: toolbar) }
        for frame in frames {
            #expect(frame.width >= 44 && frame.height >= 44)
            #expect(toolbar.bounds.contains(frame))
        }
        for index in 1..<frames.count {
            #expect(isRTL ? frames[index].maxX <= frames[index - 1].minX : frames[index].minX >= frames[index - 1].maxX)
        }
        #expect(!accounts.isHidden && accounts.isUserInteractionEnabled)
        #expect(effectViews(in: toolbar).allSatisfy { $0.alpha == 1 })
    }

    @Test(arguments: [UniversalSearchFieldPresentation.search, .compactToolbar, .empty, .sideToolbar], [false, true])
    func `optional buttons restore after navigation completes or cancels`(target: UniversalSearchFieldPresentation, cancelled: Bool) throws {
        for shared in [false, true] {
            let (window, toolbar) = makeToolbar()
            defer { window.isHidden = true }
            let configuration = HomeToolbarConfiguration(showsAccounts: true, showsScan: true, sharesBackground: shared)
            toolbar.setHomeConfiguration(configuration, animated: false)
            toolbar.setPresentation(.homeToolbar, animated: false)
            let source = try #require(toolbar.scanButtonPresentationSourceView)
            let originalFrame = source.convert(source.bounds, to: toolbar)
            let transition = try #require(toolbar.preparePresentationTransition(to: target, compactActions: tradeActions))
            toolbar.applyPreparedPresentationTransition(transition)
            #expect((toolbar.scanButtonPresentationSourceView != nil) == (target == .sideToolbar))
            #expect(toolbar.accountsButton.isUserInteractionEnabled == (target == .sideToolbar))
            #expect(effectViews(in: toolbar).allSatisfy { $0.alpha == 1 })
            toolbar.finishPreparedPresentationTransition(transition, isCancelled: cancelled)
            #expect(transitionGlassViews(in: toolbar).isEmpty)
            if !cancelled {
                let pop = try #require(toolbar.preparePresentationTransition(to: .homeToolbar, navigationOperation: .pop))
                toolbar.applyPreparedPresentationTransition(pop)
                toolbar.finishPreparedPresentationTransition(pop, isCancelled: false)
            }
            #expect(toolbar.homeConfiguration == configuration)
            #expect(toolbar.scanButtonPresentationSourceView === source)
            #expect(source.convert(source.bounds, to: toolbar) == originalFrame)
            #expect(!toolbar.accountsButton.isHidden && toolbar.accountsButton.isUserInteractionEnabled)
        }
    }

    @Test(arguments: [false, true])
    func `preference changes during navigation apply after completion or cancellation`(cancelled: Bool) throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setPresentation(.homeToolbar, animated: false)
        let transition = try #require(toolbar.preparePresentationTransition(to: .search))
        toolbar.applyPreparedPresentationTransition(transition)
        let configuration = HomeToolbarConfiguration(showsAccounts: true, showsScan: false, sharesBackground: false)
        toolbar.setHomeConfiguration(configuration, animated: false)
        #expect(toolbar.homeConfiguration != configuration)
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: cancelled)
        #expect(toolbar.homeConfiguration == configuration)
        toolbar.setPresentation(.homeToolbar, animated: false)
        #expect(toolbar.scanButtonPresentationSourceView == nil)
        #expect(!toolbar.accountsButton.isHidden)
        #expect(toolbar.accountsButton.isUserInteractionEnabled)
    }

    @Test
    func `rapid configuration changes finish at the latest settings`() async throws {
        let (window, toolbar) = makeToolbar()
        defer { window.isHidden = true }
        toolbar.setPresentation(.homeToolbar, animated: false)
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: false, sharesBackground: false), animated: true)
        try await Task.sleep(for: .milliseconds(80))
        toolbar.setHomeConfiguration(.init(showsAccounts: false, showsScan: true, sharesBackground: true), animated: true)
        try await Task.sleep(for: .milliseconds(500))
        #expect(toolbar.accountsButton.isHidden)
        #expect(toolbar.scanButtonPresentationSourceView != nil)
        #expect(effectViews(in: toolbar).allSatisfy { $0.alpha == 1 })
        let transition = try #require(toolbar.preparePresentationTransition(to: .compactToolbar, compactActions: tradeActions))
        toolbar.applyPreparedPresentationTransition(transition)
        toolbar.finishPreparedPresentationTransition(transition, isCancelled: false)
        expectVisibleActions(in: toolbar)
    }

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
        ((view as? UIVisualEffectView).map { [$0] } ?? []) + view.subviews.flatMap { effectViews(in: $0) }
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
        forceLayoutDirection(in: toolbar, isRTL: isRTL)
        toolbar.setHomeConfiguration(.init(showsAccounts: true, showsScan: true), animated: false)
        let sideFrame = CGRect(x: 420, y: 868 - toolbar.sideToolbarHeight, width: 48, height: toolbar.sideToolbarHeight)
        toolbar.frame = sideFrame
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        toolbar.setPresentation(.sideToolbar, animated: false)
        toolbar.layoutIfNeeded()
        let actionFrame = toolbar.trailingButtonView.convert(toolbar.trailingButtonView.bounds, to: toolbar)
        #expect(actionFrame == CGRect(x: 0, y: toolbar.sideToolbarHeight - 48, width: 48, height: 48))
        #expect(toolbar.hitTest(CGPoint(x: 24, y: actionFrame.midY), with: nil) != nil)
        let scan = try #require(toolbar.scanButtonPresentationSourceView)
        let scanFrame = scan.convert(scan.bounds, to: toolbar)
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
            toolbar.frame = sideFrame
            toolbar.finishPreparedPresentationTransition(transition, isCancelled: true)
        } else {
            toolbar.finishPreparedPresentationTransition(transition, isCancelled: false)
            let collapse = try #require(toolbar.preparePresentationTransition(to: .sideToolbar))
            toolbar.frame = sideFrame
            toolbar.applyPreparedPresentationTransition(collapse)
            toolbar.finishPreparedPresentationTransition(collapse, isCancelled: false)
        }
        toolbar.layoutIfNeeded()
        #expect(toolbar.presentation == .sideToolbar)
        #expect(toolbar.scanButtonPresentationSourceView === scan)
        #expect(scan.convert(scan.bounds, to: toolbar) == scanFrame)
        #expect(!toolbar.accountsButton.isHidden && toolbar.accountsButton.isUserInteractionEnabled)
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
        forceLayoutDirection(in: toolbar, isRTL: isRTL)
        toolbar.setPresentation(.compactToolbar, animated: false)
        return (window, toolbar)
    }

    private func forceLayoutDirection(in view: UIView, isRTL: Bool) {
        view.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        view.subviews.forEach { forceLayoutDirection(in: $0, isRTL: isRTL) }
        view.setNeedsLayout()
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

private final class EffectAssignments {
    var effects: [UIVisualEffect?] = []
}
