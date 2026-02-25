import UIKit
import UIComponents
import UIInAppBrowser
import UIPasscode
import WalletCore
import WalletContext

private let log = Log("RootContainerVC")

@MainActor
final class RootContainerVC: UIViewController, VisibleContentProviding {
    let contentViewController: UIViewController
    var visibleContentProviderViewController: UIViewController { contentViewController }

    private let minimizableSheetContentViewController = MinimizableSheetContentViewController()
    private lazy var sheetContainerViewController: MinimizableSheetContainerViewController = {
        var configuration = MinimizableSheetConfiguration.default
        configuration.minimizedVisibleHeight = 44
        configuration.minimizedCornerRadius = IOS_26_MODE_ENABLED ? 20 : 12
        configuration.expandedCornerRadius = IOS_26_MODE_ENABLED ? 26 : 16
        return MinimizableSheetContainerViewController(
            mainViewController: contentViewController,
            sheetViewController: minimizableSheetContentViewController,
            configuration: configuration
        )
    }()

    private var unlockVC: UnlockVC?
    
    /// Flag used to prevent a loop:
    /// -> tryBiometrics()
    /// -> Touch ID screen (app becomes inactive)
    /// -> User cancels Touch ID dialog
    /// -> App becomes active
    /// -> appDidBecomeActive()
    /// -> tryBiometrics()
    ///
    /// The flag is set to true only after the app actually goes to the background and then returns to the foreground.
    /// Be careful: due distributed locking business logic events (app activation, lock request) can go in an unpredictable order.
    private var canTryBiometrics: Bool = false

    init(contentViewController: UIViewController) {
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        addChild(sheetContainerViewController)
        sheetContainerViewController.view.frame = view.bounds
        sheetContainerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(sheetContainerViewController.view)
        sheetContainerViewController.didMove(toParent: self)

        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func showLock(animated: Bool, onUnlock: @escaping () -> Void) {
        log.info("showLock animated=\(animated)")
        guard AuthSupport.accountsSupportAppLock else { return }
        guard unlockVC == nil else { return }

        let unlockVC = UnlockVC(
            title: lang("Wallet is Locked"),
            replacedTitle: lang("Enter your Wallet Passcode"),
            animatedPresentation: true,
            dissmissWhenAuthorized: true,
            shouldBeThemedLikeHeader: true
        ) { _ in
            self.unlockVC = nil
            onUnlock()
        }
        unlockVC.modalPresentationStyle = .overFullScreen
        unlockVC.modalTransitionStyle = .crossDissolve
        unlockVC.modalPresentationCapturesStatusBarAppearance = true

        let topVC = topViewController() ?? self
        if topVC is UIActivityViewController {
            let presenting = topVC.presentingViewController!
            presenting.dismiss(animated: false) {
                self.showLock(animated: animated, onUnlock: onUnlock)
            }
        } else {
            topVC.present(unlockVC, animated: animated) { [weak self] in
                self?.unlockVC = unlockVC
                
                // In case showLock() arrived with some delay after app activation we retrying the biometrics invocation
                self?.tryBiometrics()
                log.info("showLock animated=\(animated) OK")
            }
        }

        getMenuLayerView()?.dismissMenu()
        UIApplication.shared.sceneWindows
            .flatMap(\.subviews)
            .filter { $0.description.contains("PopoverGestureContainer") }
            .forEach { $0.removeFromSuperview() }
    }

    private func tryBiometrics() {
        guard canTryBiometrics else { return }
                
        // It is necessary to check if the locking is currently enabled before clearing canAutoTryBiometrics flag because
        // this function can be called before showLock() creates the lock screen and thus the canAutoTryBiometrics value will be wasted
        guard unlockVC != nil else { return }

        // One-time attempt consumed.The flag will be set again after the app returns from background
        canTryBiometrics = false

        log.info("tryBiometrics")
        unlockVC?.tryBiometric()
    }
        
    @objc
    private func appDidBecomeActive() {
        log.info(" ")
        log.info("appDidBecomeActive")

        tryBiometrics()
    }
    
    @objc
    private func willEnterForeground() {
        log.info(" ")
        log.info("willEnterForeground")
        
        canTryBiometrics = true
        unlockVC?.passcodeScreenView?.fadeIn()
    }
}
