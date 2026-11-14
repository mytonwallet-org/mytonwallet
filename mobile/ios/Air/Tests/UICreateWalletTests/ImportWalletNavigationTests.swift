import CoreText
import XCTest
import UIKit
import UIComponents
import WalletResources
@testable import UICreateWallet

@MainActor
final class ImportWalletNavigationTests: XCTestCase {
    func testEmbeddingInstallsHiddenEditingNavigationWithoutAnAppearanceTransition() throws {
        let (host, navigation, screen) = makeEmbeddedImport()

        let proxy = try XCTUnwrap(screen.navigationItem.titleView)
        XCTAssertTrue(host.navigationItem.titleView === proxy)
        XCTAssertTrue(proxy.accessibilityElementsHidden)
        XCTAssertFalse(proxy.isUserInteractionEnabled)
        XCTAssertTrue(navigation.navigationBar.topItem === host.navigationItem)
        let appearances: [KeyPath<UINavigationItem, UINavigationBarAppearance?>] = [
            \.standardAppearance, \.scrollEdgeAppearance, \.compactAppearance, \.compactScrollEdgeAppearance,
        ]
        for keyPath in appearances {
            let expected = try XCTUnwrap(screen.navigationItem[keyPath: keyPath])
            let actual = try XCTUnwrap(host.navigationItem[keyPath: keyPath])
            XCTAssertEqual(actual.backgroundColor, expected.backgroundColor)
            XCTAssertEqual(actual.backgroundImage, expected.backgroundImage)
            XCTAssertNil(actual.backgroundEffect)
        }
    }

    func testScrollingReplacesAndRestoresTheHostsCloseButton() throws {
        let close = UIBarButtonItem(systemItem: .close)
        let (host, _, screen) = makeEmbeddedImport(closeItem: close)
        let scrollView = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? UIScrollView }.first)
        let firstInput = try XCTUnwrap(findView("import_word_1", in: screen.view)?.superview?.superview)
        let firstRow = firstInput.convert(firstInput.bounds, to: scrollView)

        scrollView.setContentOffset(CGPoint(x: 0, y: firstRow.minY - screen.view.safeAreaInsets.top - 10), animated: false)

        XCTAssertFalse(try XCTUnwrap(host.navigationItem.titleView).accessibilityElementsHidden)
        XCTAssertEqual(host.navigationItem.rightBarButtonItem?.accessibilityIdentifier, "import_paste_compact")

        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.contentInset.top), animated: false)

        XCTAssertTrue(try XCTUnwrap(host.navigationItem.titleView).accessibilityElementsHidden)
        XCTAssertTrue(host.navigationItem.rightBarButtonItem === close)
    }

    func testChangingWordCountPreservesRowsHeightAndEnteredWords() throws {
        let (_, _, screen) = makeEmbeddedImport()
        let scrollView = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? UIScrollView }.first)
        let firstField = try XCTUnwrap(findView("import_word_1", in: screen.view) as? UITextField)
        let lastField = try XCTUnwrap(findView("import_word_12", in: screen.view) as? UITextField)
        let extraField = try XCTUnwrap(findView("import_word_13", in: screen.view) as? UITextField)
        firstField.text = "word"
        extraField.text = "candle"
        let firstRowY = firstField.convert(firstField.bounds, to: scrollView).midY
        let lastRowY = lastField.convert(lastField.bounds, to: scrollView).midY
        let height = scrollView.contentSize.height
        let singleColumnWidth = firstField.bounds.width

        screen.setWordsMode(.words24)
        screen.view.layoutIfNeeded()

        XCTAssertEqual(scrollView.contentSize.height, height, accuracy: 0.5)
        XCTAssertEqual(firstField.convert(firstField.bounds, to: scrollView).midY, firstRowY, accuracy: 0.5)
        XCTAssertEqual(lastField.convert(lastField.bounds, to: scrollView).midY, lastRowY, accuracy: 0.5)
        XCTAssertEqual(extraField.convert(extraField.bounds, to: scrollView).midY, firstRowY, accuracy: 0.5)
        XCTAssertLessThan(firstField.bounds.width, singleColumnWidth)

        screen.setWordsMode(.words12)
        screen.view.layoutIfNeeded()

        XCTAssertEqual(scrollView.contentSize.height, height, accuracy: 0.5)
        XCTAssertEqual(firstField.bounds.width, singleColumnWidth, accuracy: 0.5)
        XCTAssertEqual(firstField.text, "word")
        XCTAssertEqual(extraField.text, "candle")
    }

    func testLoadingDisablesAndRestoresHostedNavigationControls() throws {
        let (host, _, screen) = makeEmbeddedImport(closeItem: UIBarButtonItem(systemItem: .close))
        let scrollView = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? UIScrollView }.first)
        let firstInput = try XCTUnwrap(findView("import_word_1", in: screen.view)?.superview?.superview)
        let firstRow = firstInput.convert(firstInput.bounds, to: scrollView)
        scrollView.setContentOffset(CGPoint(x: 0, y: firstRow.minY - screen.view.safeAreaInsets.top - 10), animated: false)
        let modeControl = try XCTUnwrap(host.navigationItem.titleView?.subviews.first as? UIControl)
        let pasteItem = try XCTUnwrap(host.navigationItem.rightBarButtonItem)
        XCTAssertEqual(pasteItem.accessibilityIdentifier, "import_paste_compact")

        screen.isLoading = true

        XCTAssertFalse(screen.view.isUserInteractionEnabled)
        XCTAssertFalse(modeControl.isUserInteractionEnabled)
        XCTAssertFalse(pasteItem.isEnabled)

        screen.isLoading = false

        XCTAssertTrue(screen.view.isUserInteractionEnabled)
        XCTAssertTrue(modeControl.isUserInteractionEnabled)
        XCTAssertTrue(pasteItem.isEnabled)
    }

    func testPushedStepUsesItsOwnNavigationItemAndPopRestoresImport() throws {
        let (host, navigation, screen) = makeEmbeddedImport()
        let proxy = try XCTUnwrap(screen.navigationItem.titleView)
        let nextStep = UIViewController()
        let nextTitle = UIView()
        let nextAppearance = UINavigationBarAppearance()
        nextAppearance.configureWithOpaqueBackground()
        nextAppearance.backgroundColor = .red
        nextStep.navigationItem.titleView = nextTitle
        nextStep.navigationItem.standardAppearance = nextAppearance

        navigation.pushViewController(nextStep, animated: false)

        XCTAssertTrue(navigation.navigationBar.topItem === nextStep.navigationItem)
        XCTAssertTrue(nextStep.navigationItem.titleView === nextTitle)
        XCTAssertEqual(nextStep.navigationItem.standardAppearance?.backgroundColor, .red)

        navigation.popViewController(animated: false)

        XCTAssertTrue(navigation.navigationBar.topItem === host.navigationItem)
        XCTAssertTrue(host.navigationItem.titleView === proxy)
    }

    func testWideLayoutCapsAndCentersFieldsAndContinue() throws {
        let (_, _, screen) = makeEmbeddedImport()
        screen.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 900)
        screen.view.layoutIfNeeded()
        let field = try XCTUnwrap(findView("import_word_1", in: screen.view)?.superview?.superview)
        let button = try XCTUnwrap(findView("import_continue", in: screen.view))
        for control in [field, button] {
            let frame = control.convert(control.bounds, to: screen.view)
            XCTAssertGreaterThan(frame.width, 300)
            XCTAssertLessThanOrEqual(frame.width, 496)
            XCTAssertEqual(frame.midX, screen.view.bounds.midX, accuracy: 0.5)
        }
    }

    func testFinalWordAndPopulatedPhraseKeepAutocompleteAvailable() throws {
        for mode in [SecretWordsMode.words12, .words24] {
            let (_, _, screen) = makeEmbeddedImport(usesKeyboardSuggestions: true)
            screen.setWordsMode(mode)
            let inputs = try (1 ... mode.wordCount).map { number in
                try XCTUnwrap(findView("import_word_\(number)", in: screen.view)?.superview?.superview as? WWordInput)
            }
            let suggestions = try XCTUnwrap(findView("mnemonicSuggestions", in: screen.view) as? WSuggestionsView)
            let actions = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? BottomActionsView }.first)
            for input in inputs.dropLast() {
                input.setText("abandon", notifyDelegate: true, goToNextInput: false)
            }
            let lastInput = try XCTUnwrap(inputs.last)

            _ = lastInput.textField(lastInput.textField, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "k")

            XCTAssertTrue(suggestions.hasSuggestions)
            XCTAssertEqual(actions.alpha, 0, "A final-word prefix must keep the bottom slot available for suggestions")
            screen.view.layoutIfNeeded()
            XCTAssertTrue(suggestions.hasSuggestions)
            XCTAssertEqual(actions.alpha, 0)

            // Match the suggestion cell's selection path, which clears suggestions after notifying the delegate.
            lastInput.setText("key", notifyDelegate: true, goToNextInput: false)

            XCTAssertFalse(suggestions.hasSuggestions)
            XCTAssertEqual(actions.alpha, 1)

            let firstInput = inputs[0]
            _ = firstInput.textField(firstInput.textField, shouldChangeCharactersIn: NSRange(location: 0, length: 7), replacementString: "ke")

            XCTAssertTrue(suggestions.hasSuggestions)
            XCTAssertEqual(actions.alpha, 0, "Editing a populated phrase must also preserve autocomplete")

            firstInput.textFieldDidEndEditing(firstInput.textField)

            XCTAssertFalse(suggestions.hasSuggestions)
            XCTAssertEqual(actions.alpha, 1, "Ending editing must restore Continue without requiring another keystroke")
        }
    }

    func testTallLayoutCanRevealEditingNavigationWithoutSoftwareKeyboard() throws {
        for size in [CGSize(width: 834, height: 1210), CGSize(width: 1024, height: 1366)] {
            let (host, _, screen) = makeEmbeddedImport()
            screen.view.frame = CGRect(origin: .zero, size: size)
            screen.view.layoutIfNeeded()
            let scrollView = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? UIScrollView }.first)
            let firstInput = try XCTUnwrap(findView("import_word_1", in: screen.view)?.superview?.superview)
            let firstRow = firstInput.convert(firstInput.bounds, to: scrollView)
            let targetOffset = firstRow.minY - screen.view.safeAreaInsets.top - 10
            let maximumOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom

            XCTAssertGreaterThanOrEqual(maximumOffset, targetOffset - 0.5)
            scrollView.setContentOffset(CGPoint(x: 0, y: min(targetOffset, maximumOffset)), animated: false)
            XCTAssertFalse(try XCTUnwrap(host.navigationItem.titleView).accessibilityElementsHidden)
            XCTAssertEqual(host.navigationItem.rightBarButtonItem?.accessibilityIdentifier, "import_paste_compact")
        }
    }

    func testSwitchingCompletePhraseToTwentyFourWordsFocusesNextWordAndKeepsContinue() throws {
        let (host, navigation, screen) = makeEmbeddedImport(usesKeyboardSuggestions: true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { screen.view.endEditing(true); window.isHidden = true }
        window.layoutIfNeeded()
        let inputs = try (1 ... 13).map { number in
            try XCTUnwrap(findView("import_word_\(number)", in: screen.view)?.superview?.superview as? WWordInput)
        }
        let suggestions = try XCTUnwrap(findView("mnemonicSuggestions", in: screen.view) as? WSuggestionsView)
        let actions = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? BottomActionsView }.first)
        let modeControl = try XCTUnwrap(host.navigationItem.titleView?.subviews.first as? UIControl)
        let twentyFourWords = try XCTUnwrap(findView("import_mode_24", in: modeControl) as? UIControl)
        for input in inputs.prefix(12) {
            input.setText("abandon", notifyDelegate: true, goToNextInput: false)
        }
        let nextInput = inputs[12]
        XCTAssertTrue(inputs[11].textField.becomeFirstResponder())

        twentyFourWords.sendActions(for: .touchUpInside)
        try sendValueChanged(from: modeControl)

        XCTAssertTrue(nextInput.textField.isFirstResponder)
        XCTAssertTrue(actions.primaryButton.isEnabled)
        XCTAssertEqual(actions.alpha, 1)

        _ = nextInput.textField(nextInput.textField, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "k")

        XCTAssertTrue(suggestions.hasSuggestions)
        XCTAssertFalse(actions.primaryButton.isEnabled)
        XCTAssertEqual(actions.alpha, 0)

        _ = nextInput.textFieldShouldClear(nextInput.textField)

        XCTAssertFalse(suggestions.hasSuggestions)
        XCTAssertTrue(actions.primaryButton.isEnabled)
        XCTAssertEqual(actions.alpha, 1)
    }

    func testTwelveWordsTypedInTwentyFourWordModeKeepContinueDisabled() throws {
        let (_, _, screen) = makeEmbeddedImport(usesKeyboardSuggestions: true)
        screen.setWordsMode(.words24)
        let actions = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? BottomActionsView }.first)
        for number in 1 ... 12 {
            let input = try XCTUnwrap(findView("import_word_\(number)", in: screen.view)?.superview?.superview as? WWordInput)
            input.setText("abandon", notifyDelegate: true, goToNextInput: false)
        }

        XCTAssertFalse(actions.primaryButton.isEnabled)
        XCTAssertEqual(actions.alpha, 0)
    }

    func testPrivateKeyStillShowsContinueWithoutFillingEveryWord() throws {
        let (_, _, screen) = makeEmbeddedImport(usesKeyboardSuggestions: true)
        let input = try XCTUnwrap(findView("import_word_1", in: screen.view)?.superview?.superview as? WWordInput)
        let suggestions = try XCTUnwrap(findView("mnemonicSuggestions", in: screen.view) as? WSuggestionsView)
        let actions = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? BottomActionsView }.first)

        input.setText(String(repeating: "1", count: 64), notifyDelegate: true, goToNextInput: false)

        XCTAssertFalse(suggestions.hasSuggestions)
        XCTAssertEqual(actions.alpha, 1)
        XCTAssertTrue(actions.primaryButton.isEnabled)
    }

    private func makeEmbeddedImport(closeItem: UIBarButtonItem? = nil, usesKeyboardSuggestions: Bool = false) -> (UIViewController, UINavigationController, ImportWalletVC) {
        _ = WalletResourcesBundle.bundle.load()
        if let url = WalletResourcesBundle.bundle.url(forResource: "CalSans-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let host = UIViewController()
        host.navigationItem.titleView = UIView()
        host.navigationItem.rightBarButtonItem = closeItem
        let navigation = UINavigationController(rootViewController: host)
        navigation.loadViewIfNeeded()
        let model = IntroModel(network: .mainnet, authMode: .requiresPasscodeSetup)
        let screen = usesKeyboardSuggestions ? KeyboardImportWalletVC(introModel: model) : ImportWalletVC(introModel: model)

        // Match the sheet's replacement path: load, then embed, without forwarding appearance callbacks.
        screen.loadViewIfNeeded()
        host.addChild(screen)
        host.view.addSubview(screen.view)
        screen.didMove(toParent: host)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        screen.view.frame = host.view.bounds
        screen.view.layoutIfNeeded()
        return (host, navigation, screen)
    }

    // Package tests run without a host app, so `UIControl` target-action dispatch does not reach targets.
    private func sendValueChanged(from control: UIControl) throws {
        let target = try XCTUnwrap(control.allTargets.compactMap { $0.base as? NSObject }.first)
        let action = try XCTUnwrap(control.actions(forTarget: target, forControlEvent: .valueChanged)?.first)
        target.perform(NSSelectorFromString(action), with: control)
    }

    private func findView(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { self.findView(identifier, in: $0) }.first
    }
}

private final class KeyboardImportWalletVC: ImportWalletVC {
    override var usesKeyboardSuggestions: Bool { true }
}
