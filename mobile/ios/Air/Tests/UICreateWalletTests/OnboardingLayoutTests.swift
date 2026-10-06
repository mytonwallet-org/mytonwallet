import CoreText
import XCTest
import UIKit
import UIComponents
import UIPasscode
import UISettings
import Ledger
import WalletResources
@testable import UICreateWallet

@MainActor
final class OnboardingLayoutTests: XCTestCase {
    func testOnboardingAndLockScreenAdaptToBothSideInsetsAndWideWindows() async throws {
        _ = WalletResourcesBundle.bundle.load()
        if let url = WalletResourcesBundle.bundle.url(forResource: "CalSans-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let words = (1...24).map { "example\($0)" }
        let model = IntroModel(network: .mainnet, authMode: .requiresPasscodeSetup, words: words)
        let passcode = SetPasscodeVC(onCompletion: { _ in })
        let screens: [WViewController] = [
            IntroVC(introModel: model),
            AboutVC(showLegalSection: false),
            UseResponsiblyVC(),
            AccountTypePickerVC(network: .mainnet),
            ImportExistingPickerVC(introModel: model),
            CreateBackupDisclaimerVC(introModel: model),
            WordDisplayVC(introModel: model, wordList: words),
            WordCheckVC(introModel: model, words: words, allWords: words),
            ImportSuccessVC(.created, introModel: model, importedAccountsCount: 1),
            ImportWalletVC(introModel: model),
            AddViewWalletVC(introModel: model, autofocusesOnAppear: false),
            passcode,
            ConfirmPasscodeVC(onCompletion: { _ in }, setPasscodeVC: passcode, selectedPasscode: "0000"),
            ActivateBiometricVC(biometryType: .face, authorizationToken: "fixture", onCompletion: { _ in }),
            LedgerAddAccountVC(model: LedgerAddAccountModel(), autoStart: false),
            LedgerSelectWalletsVC(model: LedgerAddAccountModel()),
            AppLockUnlockVC(mode: .launch, onDone: { _ in }, onSignOutRequested: {}),
            AppLockUnlockVC(mode: .app, onDone: { _ in }, onSignOutRequested: {}),
        ]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 874))
        defer { window.isHidden = true }
        for screen in screens {
            let host = UIViewController()
            window.rootViewController = host
            host.addChild(screen)
            host.view.addSubview(screen.view)
            screen.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            screen.didMove(toParent: host)
            window.makeKeyAndVisible()

            // Reuse each controller through side changes and resizing, as happens when folding or moving a window.
            for (width, height, left, right) in [
                (466.0, 678.0, 84.0, 0.0), (466, 678, 0, 84),
                (700, 874, 84, 0), (700, 874, 0, 84),
                (1024, 874, 84, 0), (1024, 874, 0, 84),
                (1366, 874, 84, 0), (1366, 874, 0, 84),
                (402, 874, 0, 0),
            ] {
                window.frame.size = CGSize(width: width, height: height)
                host.view.frame = window.bounds
                host.additionalSafeAreaInsets = UIEdgeInsets(top: 56, left: left, bottom: 0, right: right)
                screen.view.frame = host.view.bounds
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                window.layoutIfNeeded()

                let name = "\(type(of: screen))-\(Int(width))x\(Int(height))-\(Int(left))-\(Int(right))"
                let available = host.view.safeAreaLayoutGuide.layoutFrame
                let safe = screen.view.safeAreaLayoutGuide.layoutFrame
                XCTAssertEqual(screen.view.bounds.width, width, accuracy: 1, name)
                let maximumWidth: CGFloat = screen is SettingsBaseVC ? 900 : 560
                XCTAssertEqual(safe.width, min(available.width, maximumWidth), accuracy: 1, name)
                XCTAssertGreaterThanOrEqual(safe.minX, available.minX - 1, name)
                XCTAssertLessThanOrEqual(safe.maxX, available.maxX + 1, name)
                if screen is SettingsBaseVC {
                    XCTAssertEqual(safe.midX, available.midX, accuracy: 1, name)
                } else {
                    let centeredLeft = (width - safe.width) * 0.5
                    if centeredLeft < available.minX {
                        XCTAssertEqual(safe.minX, available.minX, accuracy: 1, name)
                    } else if centeredLeft + safe.width > available.maxX {
                        XCTAssertEqual(safe.maxX, available.maxX, accuracy: 1, name)
                    } else {
                        XCTAssertEqual(safe.midX, screen.view.bounds.midX, accuracy: 1, name)
                    }
                }
                for child in screen.children {
                    let childSafe = child.view.convert(child.view.safeAreaLayoutGuide.layoutFrame, to: screen.view)
                    XCTAssertGreaterThanOrEqual(childSafe.minX, safe.minX - 1, name)
                    XCTAssertLessThanOrEqual(childSafe.maxX, safe.maxX + 1, name)
                }
                checkNativeContent(screen, safe: safe, name: name)
            }
        }
    }

    func testRemovingWidthLimitRestoresAdditionalInsets() async throws {
        let screen = ResizableColumnVC()
        screen.additionalSafeAreaInsets = UIEdgeInsets(top: 20, left: 30, bottom: 10, right: 90)
        let originalInsets = screen.additionalSafeAreaInsets
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 874))
        window.rootViewController = screen
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        XCTAssertEqual(screen.view.safeAreaLayoutGuide.layoutFrame.width, 560, accuracy: 1)
        XCTAssertEqual(screen.view.safeAreaLayoutGuide.layoutFrame.midX, screen.view.bounds.midX, accuracy: 1)

        screen.widthLimit = nil
        screen.updateMaxContentWidthIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(screen.additionalSafeAreaInsets, originalInsets)
    }

    private func checkNativeContent(_ screen: WViewController, safe: CGRect, name: String) {
        let views = descendants(of: screen.view)
        if let lockScreen = screen as? AppLockUnlockVC {
            let stack = lockScreen.passcodeScreenView.subviews.compactMap { $0 as? UIStackView }.first!
            assertInsideColumn(stack, screen: screen, safe: safe, name: name)
            XCTAssertEqual(stack.convert(stack.bounds, to: screen.view).midX, safe.midX, accuracy: 1, name)
        }
        for header in views.compactMap({ $0 as? HeaderView }) {
            assertInsideColumn(header, screen: screen, safe: safe, name: name)
        }
        if screen is ImportWalletVC {
            let inputs = views.compactMap { $0 as? WWordInput }.filter { !$0.isHidden }
            XCTAssertEqual(inputs.count, 12, name)
            for input in inputs {
                assertInsideColumn(input, screen: screen, safe: safe, name: name)
            }
            for segment in views.compactMap({ $0 as? UISegmentedControl }) {
                let frame = segment.convert(segment.bounds, to: screen.view)
                XCTAssertEqual(frame.minX, safe.minX + 32, accuracy: 1, name)
                XCTAssertEqual(frame.maxX, safe.maxX - 32, accuracy: 1, name)
            }
            if let scroll = screen.view.subviews.compactMap({ $0 as? UIScrollView }).first {
                XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1, name)
            }
        }
        if screen is AddViewWalletVC, let button = screen.bottomButton,
           let address = views.compactMap({ $0 as? UITextView }).first?.superview {
            XCTAssertEqual(button.frame.minX, address.frame.minX, accuracy: 1, name)
            XCTAssertEqual(button.frame.maxX, address.frame.maxX, accuracy: 1, name)
            assertInsideColumn(button, screen: screen, safe: safe, name: name)
        }
        if screen is SetPasscodeVC || screen is ConfirmPasscodeVC {
            if let header = views.compactMap({ $0 as? HeaderView }).first,
               let keypad = views.compactMap({ $0 as? PasscodeScreenView }).first {
                XCTAssertLessThanOrEqual(header.convert(header.bounds, to: screen.view).maxY + 16, keypad.frame.minY + 1, name)
            }
            for button in views.compactMap({ $0 as? UIButton }).filter({ !$0.isHidden }) {
                assertInsideColumn(button, screen: screen, safe: safe, name: name)
                XCTAssertGreaterThanOrEqual(button.bounds.height, 54, name)
            }
        }
    }

    private func assertInsideColumn(_ view: UIView, screen: UIViewController, safe: CGRect, name: String) {
        let frame = view.convert(view.bounds, to: screen.view)
        XCTAssertGreaterThan(frame.width, 0, name)
        XCTAssertGreaterThanOrEqual(frame.minX, safe.minX - 1, name)
        XCTAssertLessThanOrEqual(frame.maxX, safe.maxX + 1, name)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private final class ResizableColumnVC: WViewController {
    var widthLimit: CGFloat? = 560
    override var maxContentWidth: CGFloat? { widthLimit }
    override var prefersViewCenteredContent: Bool { true }
}
