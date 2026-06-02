import UIKit
import WalletCore
import WalletContext

@MainActor
public final class AppLockUnlockVC: UnlockVC {
    public enum Mode {
        case launch
        case app
    }

    public init(
        mode: Mode,
        onDone: @escaping (_ passcode: String) -> Void,
        onSignOutRequested: (@MainActor () async throws -> Void)?
    ) {
        super.init(
            title: lang("Wallet is Locked"),
            replacedTitle: lang("Enter your Wallet Passcode"),
            animatedPresentation: true,
            dissmissWhenAuthorized: mode == .app,
            shouldBeThemedLikeHeader: true,
            onDone: onDone,
            onSignOutRequested: onSignOutRequested,
            successCompletionDelay: mode == .launch ? 0 : 0.4
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
