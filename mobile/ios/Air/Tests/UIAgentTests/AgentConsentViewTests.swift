import XCTest
import MetalKit
import UIKit
@testable import UIAgent
import UIComponents
import WalletContext
import WalletResources

/// The consent sheet: the Agent's name in the sheet's header, its features, the note on the data the Agent gets, and
/// the Allow button over the home indicator
@MainActor
final class AgentConsentViewTests: XCTestCase {
    override static func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// The content scrolls between the top bars and the Allow button's area, which covers the home indicator, and
    /// ends 24 pt above that area: a screen it fits on doesn't scroll at all, and a shorter one scrolls only as far as
    /// the content's end
    func testContentScrollsOnlyAsFarAsItsEnd() throws {
        for height: CGFloat in [1200, 480] {
            let controller = UIViewController()
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 100, left: 0, bottom: 34, right: 0)
            let consent = AgentConsentView()
            consent.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(consent)
            NSLayoutConstraint.activate([
                consent.topAnchor.constraint(equalTo: controller.view.topAnchor),
                consent.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
                consent.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
                consent.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
            ])
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: height))
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            consent.layoutIfNeeded()

            let scrollView = try XCTUnwrap(consent.subviews.compactMap { $0 as? UIScrollView }.first)
            let views = findDescendants(of: consent)
            let button = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "agent_consent_allow" })
            let buttonArea = try XCTUnwrap(button.superview).frame
            XCTAssertEqual(buttonArea.maxY, consent.bounds.maxY, accuracy: 0.5, "\(height): over the home indicator")
            let note = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "agent_consent_learn_more" })
            let noteBox = try XCTUnwrap(note.superview?.superview)
            let insets = scrollView.adjustedContentInset
            XCTAssertEqual(insets.top, consent.safeAreaInsets.top, accuracy: 0.5, "\(height): below the top bars")
            XCTAssertEqual(insets.bottom, buttonArea.height, accuracy: 0.5, "\(height): above the button's area, once")
            XCTAssertEqual(
                scrollView.contentSize.height,
                noteBox.convert(noteBox.bounds, to: scrollView).maxY + 24,
                accuracy: 0.5,
                "\(height): the content ends 24 pt below the note"
            )
            XCTAssertEqual(scrollView.contentOffset.y, -insets.top, accuracy: 0.5, "\(height): opens at the top")

            let isFitting = scrollView.contentSize.height + insets.top + insets.bottom <= scrollView.bounds.height
            XCTAssertEqual(isFitting, height > 1000, "\(height): the content fits on the tall screen only")
            if isFitting {
                XCTAssertFalse(scrollView.alwaysBounceVertical, "\(height): the content doesn't scroll")
            } else {
                scrollView.contentOffset.y = scrollView.contentSize.height + insets.bottom - scrollView.bounds.height
                XCTAssertEqual(
                    noteBox.convert(noteBox.bounds, to: consent).maxY + 24,
                    buttonArea.minY,
                    accuracy: 0.5,
                    "\(height): scrolled to its end, the content stops 24 pt above the button's area"
                )
            }
        }
    }

    /// The sheet shows the Agent's name in the header the app's sheets have, with a close button, and the typing row's
    /// small spinning top beside the name, which takes the finger, rather than a large one in the content
    func testSheetShowsTheAgentsNameInItsHeader() async throws {
        let presenter = UIViewController()
        let window = makeKeyWindow(showing: presenter)
        defer { window.isHidden = true }
        AgentConsentPrompt.present(from: presenter, accept: nil, onCancel: {}, onAllow: {})
        let sheet = try await waitForConsentSheet(over: presenter, in: self)
        XCTAssertEqual(sheet.title, lang("Agent"))
        XCTAssertNotNil(sheet.navigationController, "The title stands in the sheet's navigation bar")
        XCTAssertNotNil(sheet.navigationItem.rightBarButtonItem?.primaryAction, "With a close button")
        XCTAssertFalse(findDescendants(of: sheet.view).contains { $0 is AgentSpinningTopView })
        let titleView = try XCTUnwrap(sheet.navigationItem.titleView)
        let top = try XCTUnwrap(findDescendants(of: titleView).compactMap { $0 as? AgentSpinningTopView }.first)
        let bar = try XCTUnwrap(sheet.navigationController?.navigationBar)
        for _ in 0..<50 where top.bounds.isEmpty {
            bar.layoutIfNeeded()
            titleView.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        if top.bounds.isEmpty {
            // Out of a window scene the sheet doesn't finish coming up, nor its bar lay the title out; it is laid out
            // alone at the size its content gives it
            titleView.bounds = CGRect(origin: .zero, size: titleView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize))
            titleView.layoutIfNeeded()
        }
        let name = try XCTUnwrap(findDescendants(of: titleView).compactMap { $0 as? UILabel }.first { $0.text == lang("Agent") })
        XCTAssertEqual(top.bounds.size, CGSize(width: AgentTypingIndicatorCell.spinningTopSize, height: AgentTypingIndicatorCell.spinningTopSize))
        XCTAssertTrue(top.isUserInteractionEnabled, "It grows under the finger")
        let topCenter = titleView.convert(CGPoint(x: top.bounds.midX, y: top.bounds.midY), from: top)
        XCTAssertTrue(titleView.hitTest(topCenter, with: nil) === top, "The title takes no touch meant for it")
        XCTAssertLessThanOrEqual(top.frame.maxX, name.frame.minX, "Just before the name")
        XCTAssertEqual(top.frame.midY, name.frame.midY, accuracy: 0.5)
        XCTAssertEqual(name.font, NavigationHeader2.makeTitleLabel("").font, "The title the app's other sheets have")
        XCTAssertEqual(name.textColor, .label)
    }

    /// Held, the header's spinning top grows as every top does, its canvas up in the window over the header and the
    /// sheet, unclipped by the bar or the title, while the top's place and the name stay where they are; let go, it
    /// settles back into its place
    func testHeaderTopGrowsOverTheSheetWhileHeldAndTheNameStays() throws {
        let sheet = AgentConsentSheetVC(accept: nil, onError: { _ in }, onAllow: {}, onCancel: {})
        let window = makeKeyWindow(showing: WNavigationController(rootViewController: sheet))
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let titleView = try XCTUnwrap(sheet.navigationItem.titleView)
        let top = try XCTUnwrap(findDescendants(of: titleView).compactMap { $0 as? AgentSpinningTopView }.first)
        defer { top.isActive = false }
        let name = try XCTUnwrap(findDescendants(of: titleView).compactMap { $0 as? UILabel }.first { $0.text == lang("Agent") })
        sheet.navigationController?.navigationBar.layoutIfNeeded()
        titleView.layoutIfNeeded()
        XCTAssertFalse(top.bounds.isEmpty)
        let canvas = try XCTUnwrap(top.subviews.first { $0 is MTKView }, "A canvas to grow")
        let restingTop = top.convert(top.bounds, to: window)
        let restingName = name.convert(name.bounds, to: window)

        // A top of the default growth, the same size, held where the window has room
        let reference = AgentSpinningTopView()
        defer { reference.isActive = false }
        reference.frame = CGRect(x: 169, y: 400, width: top.bounds.width, height: top.bounds.height)
        window.addSubview(reference)
        reference.layoutIfNeeded()
        let referenceCanvas = try XCTUnwrap(reference.subviews.first { $0 is MTKView })
        reference.perform(NSSelectorFromString("handlePress:"), with: ConsentTopTestPress(state: .began))
        let heldSize = referenceCanvas.bounds.size
        reference.perform(NSSelectorFromString("handlePress:"), with: ConsentTopTestPress(state: .ended))

        top.perform(NSSelectorFromString("handlePress:"), with: ConsentTopTestPress(state: .began))
        XCTAssertTrue(canvas.superview === window, "Over the header and the sheet, in the window")
        XCTAssertEqual(canvas.bounds.width, heldSize.width, accuracy: 0.5, "As every top grows")
        XCTAssertEqual(canvas.bounds.height, heldSize.height, accuracy: 0.5)
        window.layoutIfNeeded()
        XCTAssertEqual(top.convert(top.bounds, to: window), restingTop, "The top's place stays")
        XCTAssertEqual(name.convert(name.bounds, to: window), restingName, "The name doesn't move")

        top.perform(NSSelectorFromString("handlePress:"), with: ConsentTopTestPress(state: .ended))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in canvas.superview === top }, object: nil)
        // It spins down before it returns, as the held top does elsewhere
        wait(for: [settled], timeout: 8)
        XCTAssertEqual(name.convert(name.bounds, to: window), restingName)
    }

    /// Closed, or allowed, while it is still coming up, the sheet waits until it is up, then closes once and carries
    /// the choice out; closed or allowed once it is up, it closes at once
    func testSheetClosedOrAllowedRightAwayClosesAndCarriesTheChoiceOut() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        for isComingUp in [true, false] {
            for isAllowed in [false, true] {
                let moment = "Allowed: \(isAllowed), coming up: \(isComingUp)"
                presentation.isFinishingAtOnce = !isComingUp
                let presenter = UIViewController()
                let window = makeKeyWindow(showing: presenter)
                defer { window.isHidden = true }
                var cancels = 0
                var allows = 0
                let dismissals = presentation.dismissalCount
                AgentConsentPrompt.present(from: presenter, accept: nil, onCancel: { cancels += 1 }, onAllow: { allows += 1 })
                let navigation = try XCTUnwrap(presentation.presentedViewController(of: presenter) as? UINavigationController)
                let sheet = try XCTUnwrap(navigation.viewControllers.first as? AgentConsentSheetVC)
                sheet.loadViewIfNeeded()
                XCTAssertEqual(presentation.isComingUp(navigation), isComingUp, moment)
                if isAllowed {
                    sheet.consentView.onContinue?()
                    sheet.consentView.onContinue?()
                } else {
                    XCTAssertTrue(sheet.accessibilityPerformEscape())
                    XCTAssertTrue(sheet.accessibilityPerformEscape())
                }
                if isComingUp {
                    // UIKit drops a dismissal asked for while the sheet comes up, so the sheet waits for it to be up
                    for _ in 0..<10 { await Task.yield() }
                    XCTAssertEqual(presentation.dismissalCount, dismissals, "\(moment): no dismissal while coming up")
                    XCTAssertEqual(cancels + allows, 0, moment)
                    presentation.finishPresenting()
                }
                for _ in 0..<300 where presentation.presentedViewController(of: presenter) != nil || cancels + allows == 0 {
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertNil(presentation.presentedViewController(of: presenter), moment)
                XCTAssertEqual(presentation.dismissalCount, dismissals + 1, "\(moment): closed once")
                XCTAssertEqual(cancels, isAllowed ? 0 : 1, moment)
                XCTAssertEqual(allows, isAllowed ? 1 : 0, moment)
            }
        }
    }

    /// Each feature's icon stands in the middle of its text, of all of its lines
    func testFeatureIconsStandInTheMiddleOfTheirText() throws {
        let consent = AgentConsentView(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
        consent.layoutIfNeeded()
        let rows = findDescendants(of: consent).compactMap { $0 as? UIStackView }.filter { $0.axis == .horizontal }
        XCTAssertEqual(rows.count, 3)
        var lineCounts: [Int] = []
        for row in rows {
            let icon = try XCTUnwrap(row.arrangedSubviews.first as? UIImageView)
            let label = try XCTUnwrap(row.arrangedSubviews.last as? UILabel)
            // The symbol's own shape, as the stack aligns it, without the padding its picture has around it
            XCTAssertEqual(icon.alignmentRect(forFrame: icon.frame).midY, label.frame.midY, accuracy: 0.5, label.text ?? "")
            lineCounts.append(Int((label.bounds.height / label.font.lineHeight).rounded()))
        }
        XCTAssertTrue(lineCounts.contains { $0 > 1 }, "A text of several lines: \(lineCounts)")
    }

    /// Allow stands as in the app's other sheets with a button at the bottom: 30 pt from the sides, on the bottom safe
    /// area, and at least 16 pt from the bottom without one
    func testAllowStandsAsInTheAppsOtherSheets() throws {
        for bottomInset: CGFloat in [34, 0] {
            let controller = UIViewController()
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 56, left: 0, bottom: bottomInset, right: 0)
            let consent = AgentConsentView()
            consent.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(consent)
            NSLayoutConstraint.activate([
                consent.topAnchor.constraint(equalTo: controller.view.topAnchor),
                consent.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
                consent.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
                consent.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
            ])
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            consent.layoutIfNeeded()
            let button = try XCTUnwrap(findDescendants(of: consent).first { $0.accessibilityIdentifier == "agent_consent_allow" })
            let frame = button.convert(button.bounds, to: consent)
            XCTAssertEqual(frame.minX, 30, accuracy: 0.5, "\(bottomInset)")
            XCTAssertEqual(consent.bounds.maxX - frame.maxX, 30, accuracy: 0.5, "\(bottomInset)")
            XCTAssertEqual(
                consent.bounds.maxY - frame.maxY,
                max(16, consent.safeAreaInsets.bottom),
                accuracy: 0.5,
                "\(bottomInset)"
            )
        }
    }

    /// The note on the data the Agent gets is a point smaller than the footnote style, scaling as it does, under its
    /// heading at the subheadline's size
    func testDataNoteIsAPointUnderFootnote() throws {
        let consent = AgentConsentView()
        let views = findDescendants(of: consent)
        let note = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "agent_consent_learn_more" } as? UITextView)
        let font = try XCTUnwrap(note.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let footnote = UIFont.preferredFont(
            forTextStyle: .footnote,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let expectedSize = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: footnote.pointSize - 1)
        XCTAssertEqual(font.pointSize, expectedSize, accuracy: 0.01)
        XCTAssertTrue(note.adjustsFontForContentSizeCategory)
        let title = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "agent_consent_title" } as? UILabel)
        XCTAssertEqual(title.font.pointSize, UIFont.preferredFont(forTextStyle: .subheadline).pointSize, accuracy: 0.01)
    }

    /// At the default text size the sheet is as tall as its content, to the pixel, on a small iPhone and a standard
    /// one, which has room for all of it: at that height the content doesn't scroll, not even a fraction of a point,
    /// and the height holds as the sheet is laid out at it
    func testSheetIsAsTallAsItsContentSoNothingScrolls() throws {
        struct Screen {
            let size: CGSize
            let top: CGFloat
            let bottom: CGFloat
            let name: String
        }
        let screens = [
            Screen(size: CGSize(width: 375, height: 667), top: 20, bottom: 0, name: "iPhone SE"),
            Screen(size: CGSize(width: 402, height: 874), top: 62, bottom: 34, name: "iPhone 17 Pro"),
        ]
        for screen in screens {
            let sheet = AgentConsentSheetVC(accept: nil, onError: { _ in }, onAllow: {}, onCancel: {})
            let navigation = WNavigationController(rootViewController: sheet)
            let window = UIWindow(frame: CGRect(origin: .zero, size: screen.size))
            window.rootViewController = navigation
            window.isHidden = false
            defer { window.isHidden = true }
            // The sheet's safe areas are a sheet's on this screen at every height, whatever the simulator's device
            // gives the test's window: no status bar over the header, and the screen's bottom inset, which the
            // detent adds
            func pinSafeAreas() {
                navigation.additionalSafeAreaInsets = .zero
                window.layoutIfNeeded()
                let windowInsets = navigation.view.safeAreaInsets
                navigation.additionalSafeAreaInsets = UIEdgeInsets(
                    top: -windowInsets.top, left: 0, bottom: screen.bottom - windowInsets.bottom, right: 0
                )
                window.layoutIfNeeded()
                // The navigation controller gives the sheet the insets under its bar from where the bar stood before
                // this layout, under the window's status bar, and lays itself out again only when asked to; the
                // sheet then follows its new insets in a layout of its own
                navigation.view.setNeedsLayout()
                window.layoutIfNeeded()
                window.layoutIfNeeded()
                XCTAssertEqual(navigation.view.safeAreaInsets.top, 0, accuracy: 0.001, "\(screen.name): no status bar")
                XCTAssertEqual(navigation.view.safeAreaInsets.bottom, screen.bottom, accuracy: 0.001, "\(screen.name)")
                XCTAssertEqual(
                    sheet.view.safeAreaInsets.top, navigation.navigationBar.frame.maxY, accuracy: 0.001,
                    "\(screen.name): under the header alone"
                )
            }
            pinSafeAreas()
            let height = sheet.sheetHeight
            let scale = max(1, sheet.traitCollection.displayScale)
            XCTAssertEqual((height * scale).rounded(), height * scale, accuracy: 0.001, "\(screen.name): on a pixel")
            if screen.bottom > 0 {
                XCTAssertLessThan(
                    height + screen.bottom, screen.size.height - screen.top - 16,
                    "\(screen.name): all of it fits under the status bar"
                )
            }

            // As the sheet shows at its detent: that tall over the bottom safe area
            window.frame.size.height = height + screen.bottom
            pinSafeAreas()
            sheet.consentView.layoutIfNeeded()
            XCTAssertEqual(sheet.sheetHeight, height, "\(screen.name): the height holds")
            let scrollView = try XCTUnwrap(sheet.consentView.subviews.compactMap { $0 as? UIScrollView }.first)
            let insets = scrollView.adjustedContentInset
            XCTAssertLessThanOrEqual(
                scrollView.contentSize.height + insets.top + insets.bottom, scrollView.bounds.height + 0.001,
                "\(screen.name): nothing to scroll"
            )
            XCTAssertGreaterThan(scrollView.contentSize.height, 0)
        }
    }
}

/// A press on a spinning top in the state the test gives, at the top's middle
private final class ConsentTopTestPress: UILongPressGestureRecognizer {
    private let reportedState: UIGestureRecognizer.State

    init(state: UIGestureRecognizer.State) {
        reportedState = state
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { }
    }

    override func location(in view: UIView?) -> CGPoint {
        view.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) } ?? .zero
    }
}
