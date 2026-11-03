import Testing
import SwiftUI
import UIKit
import UIComponents
import UIPasscode
@testable import UIProtectedAction
import WalletCore
import WalletResources

@MainActor @Suite(.serialized)
struct ConfirmationSheetSizingTests {
    @Test(arguments: [false, true], [CGSize(width: 640, height: 700), CGSize(width: 580, height: 480)])
    func `pushed passcode preserves the flow sheet size`(sizesRoot: Bool, size: CGSize) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(wereAnimationsEnabled) }
        let source = WViewController()
        let navigation = WNavigationController(rootViewController: source)
        if sizesRoot {
            source.preferredContentSize = size
        } else {
            navigation.preferredContentSize = size
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        navigation.beginAppearanceTransition(true, animated: false)
        navigation.endAppearanceTransition()
        await settle(navigation)
        let originalSize = navigation.preferredContentSize

        let fullHeader = PasswordPresenter.makeHeaderController(rootView: Text("1 TON").frame(height: 220))
        let compactHeader = PasswordPresenter.makeHeaderController(rootView: Text("Unstake 1 TON").frame(height: 60))

        let confirmation = try #require(UnlockVC.pushAuth(
            on: source, title: "Confirm Unstaking", customHeaderVC: fullHeader, compactHeaderVC: compactHeader,
            useBioOnPresent: false, biometricPassAllowed: false,
            onAuthTask: { _, _ in Issue.record("Must not authorize") },
            onDone: { _ in Issue.record("Must not authorize") }
        ))
        await settle(navigation)
        #expect(navigation.topViewController === confirmation)
        #expect(navigation.preferredContentSize == originalSize)
        let keys = descendants(of: confirmation.view).filter {
            $0.accessibilityIdentifier?.hasPrefix("passcode_key_") == true
        }
        #expect(keys.count == 12)
        for key in keys {
            let frame = key.convert(key.bounds, to: confirmation.view)
            #expect(frame.height >= 54)
            #expect(frame.minY >= confirmation.view.safeAreaLayoutGuide.layoutFrame.minY)
            #expect(frame.maxY <= confirmation.view.safeAreaLayoutGuide.layoutFrame.maxY + 1)
        }
        navigation.popViewController(animated: true)
        await settle(navigation)
        #expect(navigation.preferredContentSize == originalSize)

        navigation.pushViewController(confirmation, animated: true)
        await settle(navigation)
        #expect(navigation.preferredContentSize == originalSize)

        let mfa = makeMfaConfirmation()
        #expect(AuthorizationSupport.push(mfa, replacing: confirmation, in: navigation))
        await settle(navigation)
        #expect(!navigation.viewControllers.contains(confirmation))
        #expect(navigation.preferredContentSize == originalSize)

        // Completion screens explicitly choose their own size on the navigation controller
        navigation.preferredContentSize = CGSize(width: 580, height: 600)
        await settle(navigation)
        #expect(navigation.preferredContentSize.width == 580)
        #expect(navigation.preferredContentSize.height >= 600)
        #expect(navigation.preferredContentSize != originalSize)
        navigation.popViewController(animated: false)
    }

    @Test
    func `standalone passcode retains its size when replaced by MFA`() async {
        _ = WalletResourcesBundle.bundle.load()
        let confirmation = UnlockVC(
            title: "Confirm", customHeaderVC: UIViewController(), dissmissWhenAuthorized: false,
            onDone: { _ in Issue.record("Must not authorize") }, biometricPassAllowed: false
        )
        let navigation = WNavigationController(rootViewController: confirmation)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1194, height: 834))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        navigation.beginAppearanceTransition(true, animated: false)
        navigation.endAppearanceTransition()
        await settle(navigation)
        let originalSize = navigation.preferredContentSize
        #expect(originalSize.width == 640)
        #expect(originalSize.height >= 800)

        let mfa = makeMfaConfirmation()
        #expect(AuthorizationSupport.push(mfa, replacing: confirmation, in: navigation))
        await settle(navigation)
        #expect(navigation.viewControllers == [mfa])
        #expect(navigation.preferredContentSize == originalSize)
        navigation.setViewControllers([UIViewController()], animated: false)
    }

    private func makeMfaConfirmation() -> MfaConfirmationVC {
        MfaConfirmationVC(
            account: MAccount(id: "sheet-sizing-mainnet", title: "Wallet", type: .mnemonic, byChain: [:]),
            model: MfaConfirmationModel(requestHash: "sheet-sizing", fetchRequest: { _ in
                try await Task.sleep(for: .seconds(60))
                throw CancellationError()
            }),
            title: "Confirm Unstaking",
            compactRepresentation: AnyView(Text("1 TON")),
            prefersNavigationTitleWithCustomHeader: true
        )
    }

    private func settle(_ navigation: UINavigationController) async {
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(30))
            navigation.view.layoutIfNeeded()
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
