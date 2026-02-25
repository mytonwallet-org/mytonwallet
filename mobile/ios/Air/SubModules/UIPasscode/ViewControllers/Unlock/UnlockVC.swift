//
//  UnlockVC.swift
//  UIPasscode
//
//  Created by Sina on 4/28/23.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

// Used for AppUnlock and other actions that require user to unlock using passcode or biometric, first.
public class UnlockVC: WViewController {
    
    public static func pushAuth(
        on vc: UIViewController,
        title: String,
        customHeaderVC: UIViewController,
        onAuthTask: @escaping (_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void,
        onDone: @escaping (_ passcode: String) -> Void
    ) {
        
        let unlockVC = UnlockVC(
            title: title,
            replacedTitle: nil,
            subtitle: nil,
            customHeaderVC: customHeaderVC,
            animatedPresentation: false,
            dissmissWhenAuthorized: false,
            shouldBeThemedLikeHeader: false,
            onAuthTask: onAuthTask,
            onDone: onDone,
            cancellable: false,
            onCancel: nil,
            useBioOnPresent: true
        )
        vc.navigationController?.pushViewController(unlockVC, animated: true)
    }
    
    /// Should be called before auth required actions
    ///  This function first, tries to unlock using biometric, if is activated and then, present this VC if failed.
    public static func presentAuth(
        on vc: UIViewController,
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        onAuthTask: ((_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void)? = nil,
        onDone: @escaping (_ passcode: String?) -> Void,
        cancellable: Bool,
        onCancel: (() -> Void)? = nil
    ) {

        guard AuthSupport.accountsSupportAppLock else {
            onDone(nil)
            return
        }
        
        func _makeUnlockVC(useBioOnPresent: Bool) -> UIViewController {
            let unlockVC =  UnlockVC(
                title: title,
                replacedTitle: replacedTitle,
                subtitle: subtitle,
                customHeaderVC: customHeaderVC,
                dissmissWhenAuthorized: false,
                onAuthTask: onAuthTask,
                onDone: onDone,
                cancellable: cancellable,
                onCancel: onCancel,
                useBioOnPresent: useBioOnPresent
            )
            if cancellable {
                let navVC = WNavigationController(rootViewController: unlockVC)
                navVC.navigationBar.tintColor = WTheme.balanceHeaderView.headIcons
                return navVC
            } else {
                return unlockVC
            }
        }
        
        let canUseBiometric = AppStorageHelper.isBiometricActivated() && BiometricHelper.biometryType != nil
        if onAuthTask == nil && canUseBiometric {
            Task { @MainActor [weak vc] in
                let result = await BiometricHelper.authenticate()
                switch result {
                case .success:
                    let passcode = KeychainHelper.biometricPasscode()
                    do {
                        guard try await AuthSupport.verifyPassword(password: passcode) else {
                            vc?.present(_makeUnlockVC(useBioOnPresent: false), animated: true)
                            return
                        }
                        onDone(passcode)
                    } catch {
                        vc?.present(_makeUnlockVC(useBioOnPresent: false), animated: true)
                    }
                    
                case .canceled, .error, .userDeniedBiometrics:
                    vc?.present(_makeUnlockVC(useBioOnPresent: false), animated: true)
                }
            }
        } else {
            // can use bio, but because of `onAuthTask`, first present unlock vc for sure!
            vc.present(_makeUnlockVC(useBioOnPresent: canUseBiometric), animated: true)
        }
    }
    
    /// Should be called before auth required actions
    /// This function first, tries to unlock using biometric, if is activated and then, present this VC if failed.
    @MainActor public static func presentAuthAsync(
        on vc: UIViewController,
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        authTask: (@MainActor (_ passcode: String) async -> Void)? = nil
    ) async -> String? {
        
        guard AuthSupport.accountsSupportAppLock else {
            return nil
        }
        
        var onAuthTask: ((_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void)? = nil
        if let authTask {
            onAuthTask = { passcode, onTaskDone in
                Task {
                    await authTask(passcode)
                    onTaskDone()
                }
            }
        }
        let lock = NSLock()

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var nillableContinuation: CheckedContinuation<String?, Never>? = continuation

            presentAuth(
                on: vc,
                title: title,
                replacedTitle: replacedTitle,
                subtitle: subtitle,
                customHeaderVC: customHeaderVC,
                onAuthTask: onAuthTask,
                onDone: { password in
                    lock.lock()
                    defer { lock.unlock() }
                    nillableContinuation?.resume(returning: password)
                    nillableContinuation = nil
                },
                cancellable: true,
                onCancel: {
                    lock.lock()
                    defer { lock.unlock() }
                    nillableContinuation?.resume(returning: nil)
                    nillableContinuation = nil
                }
            )
        }
    }
    
    private let unlockTitle: String
    private let replacedTitle: String?
    private let subtitle: String?
    private let customHeaderVC: UIViewController?
    private let animatedPresentation: Bool
    private let dissmissWhenAuthorized: Bool
    private let shouldBeThemedLikeHeader: Bool
    private var onAuthTask: ((_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void)?
    private var onDoneCallback: ((_ passcode: String) -> Void)? = nil
    private let cancellable: Bool
    private let onCancel: (() -> Void)?
    private let useBioOnPresent: Bool
    private var viewStartedDismissing: Bool = false
    private var cancelOnDisappear = true
    
    public init(
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        animatedPresentation: Bool = false,
        dissmissWhenAuthorized: Bool,
        shouldBeThemedLikeHeader: Bool = false,
        onAuthTask: ((_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void)? = nil,
        onDone: @escaping (_ passcode: String) -> Void,
        cancellable: Bool = false,
        onCancel: (() -> Void)? = nil,
        useBioOnPresent: Bool = false
    ) {
        self.unlockTitle = title
        self.replacedTitle = replacedTitle
        self.subtitle = subtitle
        self.customHeaderVC = customHeaderVC
        self.animatedPresentation = animatedPresentation
        self.dissmissWhenAuthorized = dissmissWhenAuthorized
        self.shouldBeThemedLikeHeader = shouldBeThemedLikeHeader
        self.onAuthTask = onAuthTask
        self.onDoneCallback = onDone
        self.cancellable = cancellable
        self.onCancel = onCancel
        self.useBioOnPresent = useBioOnPresent
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if useBioOnPresent {
            passcodeScreenView.tryBiometric()
        }
    }
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        if WTheme.primaryButton.background == .label {
            return .default
        }
        return .lightContent
    }
    
    private(set) public var passcodeScreenView: PasscodeScreenView!
    private var indicatorView: WActivityIndicator!
    
    var shouldShowEmptyNavigationBar: Bool {
        IOS_26_MODE_ENABLED && customHeaderVC != nil
    }

    public override var hideNavigationBar: Bool {
        return !IOS_26_MODE_ENABLED && customHeaderVC != nil
    }
    
    public override func viewIsAppearing(_ animated: Bool) {
        if shouldShowEmptyNavigationBar,
           let navbarHeight = navigationController?.navigationBar.frame.height {
            if IOS_26_MODE_ENABLED {
                additionalSafeAreaInsets.top = -navbarHeight
            }
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.viewStartedDismissing = true
    }
    
    private func setupViews() {
        
        let compactLayout = customHeaderVC != nil
        let showNavBar = compactLayout
        let customHeader = customHeaderVC?.view
        
        // legacy
        if cancellable && !compactLayout {
            addCloseNavigationItemIfNeeded()
        }

        // init views
        
        if shouldShowEmptyNavigationBar {
            addNavigationBar(
                centerYOffset: 1,
                title: nil,
                closeIcon: false,
                addBackButton: { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                }
            )
        } else if showNavBar {
            addNavigationBar(
                centerYOffset: 1,
                title: unlockTitle,
                closeIcon: true,
                addBackButton: { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                }
            )
            navigationItem.hidesBackButton = true
        }
        
        passcodeScreenView = PasscodeScreenView(
            title: unlockTitle,
            replacedTitle: replacedTitle,
            subtitle: subtitle,
            compactLayout: customHeader != nil,
            biometricPassAllowed: true,
            delegate: self,
            matchHeaderColors: shouldBeThemedLikeHeader
        )
        if compactLayout {
            view.backgroundColor = WTheme.sheetBackground
            passcodeScreenView.layer.cornerRadius = 16
        }
        indicatorView = WActivityIndicator()

        // add subviews
        
        if let customHeaderVC {
            addChild(customHeaderVC)
            view.addSubview(customHeaderVC.view)
            customHeaderVC.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                customHeaderVC.view.topAnchor.constraint(equalTo: navigationBarAnchor),
                customHeaderVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                customHeaderVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            customHeaderVC.didMove(toParent: self)
        }
        
        view.addSubview(passcodeScreenView)
        passcodeScreenView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            passcodeScreenView.leftAnchor.constraint(equalTo: view.leftAnchor),
            passcodeScreenView.rightAnchor.constraint(equalTo: view.rightAnchor),
            passcodeScreenView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if let customHeader {
            passcodeScreenView.topAnchor.constraint(equalTo: customHeader.bottomAnchor).isActive = true
        } else {
            passcodeScreenView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        }
        
        view.addSubview(indicatorView)
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicatorView.centerXAnchor.constraint(equalTo: passcodeScreenView.passcodeInputView.centerXAnchor),
            indicatorView.centerYAnchor.constraint(equalTo: passcodeScreenView.passcodeInputView.centerYAnchor),
        ])
        
        bringNavigationBarToFront()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if animatedPresentation {
            view.backgroundColor = .clear
            passcodeScreenView.fadeIn()
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        if cancelOnDisappear {
            self.onCancel?()
        }
        super.viewDidDisappear(animated)
    }

    // when this function is called, `UnlockVC` tries to use biometric
    public func tryBiometric() {
        passcodeScreenView.tryBiometric()
    }
    
    public override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        // do not allow this
    }
}

extension UnlockVC: PasscodeScreenViewDelegate {
    func passcodeChanged(passcode: String) {
    }
    
    func passcodeSelected(passcode: String) {
        passcodeScreenView.isUserInteractionEnabled = false
        Task { @MainActor [weak self] in
            let success: Bool
            do {
                success = try await AuthSupport.verifyPassword(password: passcode)
            } catch let error as AuthCooldownError {
                self?.showCooldownAlert(error: error)
                success = false
            } catch {
                success = false
            }
            guard let self else { return }
            if success {
                animateSuccess()
                try? await Task.sleep(for: .seconds(0.4))
                onAuthenticated(taskDone: false, passcode: passcode)
            } else {
                try? await Task.sleep(for: .seconds(0.2))
                passcodeScreenView.isUserInteractionEnabled = true
                passcodeScreenView.passcodeInputView.currentPasscode = ""
                passcodeScreenView.wrongPassFeedback()
                Haptics.play(.error)
            }
        }
    }
    
    func showCooldownAlert(error: AuthCooldownError) {
        let time = formatTimeInterval(error.waitFor)
        let alert = alert(
            title: "Cooldown",
            text: "Please wait for \(time) before trying again.",
            button: "OK",
            buttonStyle: .default,
            buttonPressed: nil,
            secondaryButton: nil,
            secondaryButtonPressed: nil,
            preferPrimary: true
        )
        super.present(alert, animated: true, completion: nil)
    }
    
    @MainActor func animateSuccess() {
        passcodeScreenView.passcodeInputView.animateSuccess()
        guard onAuthTask != nil else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            indicatorView.alpha = 0
            indicatorView.transform = .init(scaleX: 0.2, y: 0.2)
            UIView.animate(withDuration: 0.2, delay: 0, options: []) { [weak self] in
                guard let self else { return }
                passcodeScreenView.passcodeInputView.alpha = 0
                indicatorView.alpha = 1
                indicatorView.transform = .identity
                indicatorView.startAnimating(animated: true)
            }
        }
    }

    func onAuthenticated(taskDone: Bool, passcode: String) {
        navigationItem.setHidesBackButton(true, animated: true)
        Haptics.prepare(.success)
        if taskDone == false && (isBeingDismissed || view.superview == nil || viewStartedDismissing)  {
            return
        }
        if let onAuthTask, taskDone == false {
            onAuthTask(passcode) {
                DispatchQueue.main.async { [weak self] in
                    self?.onAuthenticated(taskDone: true, passcode: passcode)
                }
            }
            self.onAuthTask = nil
            return
        }
        // onAuthTask is completed or not set
        cancelOnDisappear = false
        if animatedPresentation {
            if dissmissWhenAuthorized {
                UIView.animate(withDuration: 0.2) {
                    self.passcodeScreenView.alpha = 0
                } completion: { [weak self] _ in
                    self?.dismiss(animated: false, completion: {
                        self?.onDoneCallback?(passcode)
                        self?.onDoneCallback = nil
                    })
                }
            } else {
                self.onDoneCallback?(passcode)
                self.onDoneCallback = nil
            }
        } else {
            if customHeaderVC != nil {
                self.onDoneCallback?(passcode)
                self.onDoneCallback = nil
            } else {
                dismiss(animated: true) { [weak self] in
                    self?.onDoneCallback?(passcode)
                    self?.onDoneCallback = nil
                }
            }
        }
    }
}
