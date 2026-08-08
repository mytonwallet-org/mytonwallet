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

    @discardableResult
    public static func pushAuth(
        on vc: UIViewController,
        title: String,
        customHeaderVC: UIViewController,
        compactHeaderVC: UIViewController? = nil,
        sessionKind: AuthSessionKind = .oneShot,
        useBioOnPresent: Bool = true,
        biometricPassAllowed: Bool = true,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        onAuthTask: @escaping (_ enclaveToken: EnclaveToken, _ onTaskDone: @escaping () -> Void) -> Void,
        onDone: @escaping (_ enclaveToken: EnclaveToken) -> Void,
        onCancel: (() -> Void)? = nil
    ) -> UnlockVC? {
        PasscodeAuthPresenter.push(
            on: vc,
            title: title,
            customHeaderVC: customHeaderVC,
            compactHeaderVC: compactHeaderVC,
            sessionKind: sessionKind,
            useBioOnPresent: useBioOnPresent,
            biometricPassAllowed: biometricPassAllowed,
            prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
            onAuthTask: onAuthTask,
            onDone: onDone,
            onCancel: onCancel
        )
    }

    /// Should be called before auth required actions.
    /// Presents unlock UI and optionally auto-triggers biometric auth on appear.
    public static func presentAuth(
        on vc: UIViewController,
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        compactHeaderVC: UIViewController? = nil,
        sessionKind: AuthSessionKind = .oneShot,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        onAuthTask: ((_ enclaveToken: EnclaveToken, _ onTaskDone: @escaping () -> Void) -> Void)? = nil,
        onDone: @escaping (_ enclaveToken: EnclaveToken?) -> Void,
        cancellable: Bool,
        onCancel: (() -> Void)? = nil
    ) {
        guard AuthSupport.status.requiresAuthorization else {
            onDone(nil)
            return
        }

        func _makeUnlockVC(useBioOnPresent: Bool) -> UIViewController {
            let unlockVC =  UnlockVC(
                title: title,
                replacedTitle: replacedTitle,
                subtitle: subtitle,
                customHeaderVC: customHeaderVC,
                compactHeaderVC: compactHeaderVC,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                dissmissWhenAuthorized: false,
                onAuthTask: onAuthTask,
                onDone: onDone,
                cancellable: cancellable,
                onCancel: onCancel,
                useBioOnPresent: useBioOnPresent,
                authSessionKind: sessionKind
            )
            if cancellable {
                let navVC = WNavigationController(rootViewController: unlockVC)
                navVC.navigationBar.tintColor = AirTintColor
                return navVC
            } else {
                return unlockVC
            }
        }

        let canUseBiometric = AuthSupport.status.authorizableMethods.contains(.biometrics)
        vc.present(_makeUnlockVC(useBioOnPresent: canUseBiometric), animated: true)
    }

    /// Should be called before auth required actions.
    @MainActor public static func presentAuthAsync(
        on vc: UIViewController,
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        compactHeaderVC: UIViewController? = nil,
        sessionKind: AuthSessionKind = .oneShot,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        authTask: (@MainActor (_ enclaveToken: EnclaveToken) async -> Void)? = nil
    ) async -> EnclaveToken? {

        guard AuthSupport.status.requiresAuthorization else {
            return nil
        }

        var onAuthTask: ((_ enclaveToken: EnclaveToken, _ onTaskDone: @escaping () -> Void) -> Void)? = nil
        if let authTask {
            onAuthTask = { enclaveToken, onTaskDone in
                Task {
                    await authTask(enclaveToken)
                    onTaskDone()
                }
            }
        }
        let lock = NSLock()

        return await withCheckedContinuation { (continuation: CheckedContinuation<EnclaveToken?, Never>) in
            var nillableContinuation: CheckedContinuation<EnclaveToken?, Never>? = continuation

            presentAuth(
                on: vc,
                title: title,
                replacedTitle: replacedTitle,
                subtitle: subtitle,
                customHeaderVC: customHeaderVC,
                compactHeaderVC: compactHeaderVC,
                sessionKind: sessionKind,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                onAuthTask: onAuthTask,
                onDone: { enclaveToken in
                    lock.lock()
                    defer { lock.unlock() }
                    nillableContinuation?.resume(returning: enclaveToken)
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
    private let compactHeaderVC: UIViewController?
    private let prefersNavigationTitleWithCustomHeader: Bool
    private let animatedPresentation: Bool
    private let dissmissWhenAuthorized: Bool
    private let shouldBeThemedLikeHeader: Bool
    private var onAuthTask: ((_ enclaveToken: EnclaveToken, _ onTaskDone: @escaping () -> Void) -> Void)?
    private var onDoneCallback: ((_ enclaveToken: EnclaveToken) -> Void)? = nil
    private let cancellable: Bool
    private let onCancel: (() -> Void)?
    private let onSignOutRequested: (@MainActor () async throws -> Void)?
    private let useBioOnPresent: Bool
    private let biometricPassAllowed: Bool
    private let authSessionKind: AuthSessionKind
    private let successCompletionDelay: TimeInterval
    private var didTryBiometricOnPresent = false
    private var viewStartedDismissing: Bool = false
    private var cancelOnDisappear = true
    private var didCancel = false
    private var authorizationTaskStarted = false
    private weak var authorizationNavigationController: UINavigationController?
    private var wasModalInPresentation = false
    private var wasBackSwipeToDismissAllowed = true
    private var showsSignOutWhenEmpty = false
    private var passcodeTopConstraint: NSLayoutConstraint?
    private var isUsingCompactHeader = false

    public init(
        title: String = lang("Enter your Wallet Passcode"),
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        customHeaderVC: UIViewController? = nil,
        compactHeaderVC: UIViewController? = nil,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        animatedPresentation: Bool = false,
        dissmissWhenAuthorized: Bool,
        shouldBeThemedLikeHeader: Bool = false,
        onAuthTask: ((_ enclaveToken: EnclaveToken, _ onTaskDone: @escaping () -> Void) -> Void)? = nil,
        onDone: @escaping (_ enclaveToken: EnclaveToken) -> Void,
        cancellable: Bool = false,
        onCancel: (() -> Void)? = nil,
        useBioOnPresent: Bool = false,
        biometricPassAllowed: Bool = true,
        authSessionKind: AuthSessionKind = .oneShot,
        onSignOutRequested: (@MainActor () async throws -> Void)? = nil,
        successCompletionDelay: TimeInterval = 0.4
    ) {
        self.unlockTitle = title
        self.replacedTitle = replacedTitle
        self.subtitle = subtitle
        self.customHeaderVC = customHeaderVC
        self.compactHeaderVC = compactHeaderVC
        self.prefersNavigationTitleWithCustomHeader = prefersNavigationTitleWithCustomHeader
        self.animatedPresentation = animatedPresentation
        self.dissmissWhenAuthorized = dissmissWhenAuthorized
        self.shouldBeThemedLikeHeader = shouldBeThemedLikeHeader
        self.onAuthTask = onAuthTask
        self.onDoneCallback = onDone
        self.cancellable = cancellable
        self.onCancel = onCancel
        self.onSignOutRequested = onSignOutRequested
        self.useBioOnPresent = useBioOnPresent
        self.biometricPassAllowed = biometricPassAllowed
        self.authSessionKind = authSessionKind
        self.successCompletionDelay = successCompletionDelay
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
        viewStartedDismissing = false
        tryBiometricOnPresentIfNeeded()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderForAvailableHeight()
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        if AirTintColor == .label {
            return .default
        }
        return .lightContent
    }

    private(set) public var passcodeScreenView: PasscodeScreenView!
    private var indicatorView: WActivityIndicator!

    var shouldShowEmptyNavigationBar: Bool {
        IOS_26_MODE_ENABLED && customHeaderVC != nil && !prefersNavigationTitleWithCustomHeader
    }

    public override var hideNavigationBar: Bool {
        false
    }

    public override func viewIsAppearing(_ animated: Bool) {
        if shouldShowEmptyNavigationBar,
           let navbarHeight = navigationController?.navigationBar.frame.height {
            if IOS_26_MODE_ENABLED {
                additionalSafeAreaInsets.top = -navbarHeight
            }
        } else {
            additionalSafeAreaInsets.top = 0
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

        if showNavBar {
            navigationItem.title = shouldShowEmptyNavigationBar ? nil : unlockTitle
            addCloseNavigationItemIfNeeded()
        }

        showsSignOutWhenEmpty = onSignOutRequested != nil && AuthSupport.cooldownRemaining != nil

        passcodeScreenView = PasscodeScreenView(
            title: unlockTitle,
            replacedTitle: replacedTitle,
            subtitle: subtitle,
            compactLayout: customHeader != nil,
            biometricPassAllowed: biometricPassAllowed,
            authSessionKind: authSessionKind,
            allowsSignOutWhenEmpty: onSignOutRequested != nil,
            showsSignOutWhenEmpty: showsSignOutWhenEmpty,
            delegate: self,
            matchHeaderColors: shouldBeThemedLikeHeader
        )
        if compactLayout {
            view.backgroundColor = .air.sheetBackground
            passcodeScreenView.layer.cornerRadius = 16
        }
        indicatorView = WActivityIndicator()

        // add subviews

        if let customHeaderVC {
            installHeader(customHeaderVC)
        }
        if let compactHeaderVC {
            installHeader(compactHeaderVC)
            compactHeaderVC.view.isHidden = true
        }

        view.addSubview(passcodeScreenView)
        passcodeScreenView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            passcodeScreenView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            passcodeScreenView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            passcodeScreenView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if let customHeader {
            passcodeTopConstraint = passcodeScreenView.topAnchor.constraint(equalTo: customHeader.bottomAnchor)
            passcodeTopConstraint?.isActive = true
        } else {
            passcodeScreenView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        }

        view.addSubview(indicatorView)
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicatorView.centerXAnchor.constraint(equalTo: passcodeScreenView.passcodeInputView.centerXAnchor),
            indicatorView.centerYAnchor.constraint(equalTo: passcodeScreenView.passcodeInputView.centerYAnchor),
        ])
    }

    private func installHeader(_ viewController: UIViewController) {
        addChild(viewController)
        view.addSubview(viewController.view)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        viewController.didMove(toParent: self)
    }

    private func updateHeaderForAvailableHeight() {
        guard let customHeaderVC, let compactHeaderVC, view.bounds.width > 0 else { return }

        let width = view.bounds.width
        let fullHeaderHeight = fittingHeight(of: customHeaderVC.view, width: width)
        let passcodeHeight = fittingHeight(of: passcodeScreenView, width: width)
        let availableHeight = view.bounds.height - view.safeAreaInsets.top
        let shouldUseCompactHeader = fullHeaderHeight + passcodeHeight > availableHeight

        guard shouldUseCompactHeader != isUsingCompactHeader else { return }
        isUsingCompactHeader = shouldUseCompactHeader

        passcodeTopConstraint?.isActive = false
        customHeaderVC.view.isHidden = shouldUseCompactHeader
        compactHeaderVC.view.isHidden = !shouldUseCompactHeader
        let activeHeader = shouldUseCompactHeader ? compactHeaderVC.view! : customHeaderVC.view!
        passcodeTopConstraint = passcodeScreenView.topAnchor.constraint(equalTo: activeHeader.bottomAnchor)
        passcodeTopConstraint?.isActive = true
    }

    private func fittingHeight(of view: UIView, width: CGFloat) -> CGFloat {
        view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if animatedPresentation {
            view.backgroundColor = .clear
            passcodeScreenView.fadeIn()
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        if authorizationTaskStarted {
            authorizationNavigationController?.allowBackSwipeToDismiss(wasBackSwipeToDismissAllowed)
            authorizationNavigationController?.isModalInPresentation = wasModalInPresentation
            authorizationNavigationController = nil
        }
        if cancelOnDisappear, !didCancel {
            didCancel = true
            self.onCancel?()
        }
        super.viewDidDisappear(animated)
    }

    // when this function is called, `UnlockVC` tries to use biometric
    public func tryBiometric() {
        loadViewIfNeeded()
        passcodeScreenView?.tryBiometric()
    }

    private func tryBiometricOnPresentIfNeeded() {
        guard useBioOnPresent, !didTryBiometricOnPresent else { return }
        didTryBiometricOnPresent = true
        passcodeScreenView.tryBiometric()
    }

    public override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        // do not allow this
    }
}

extension UnlockVC: PasscodeScreenViewDelegate {
    func passcodeChanged(passcode: String) {
        passcodeScreenView.setShowsSignOutWhenEmpty(showsSignOutWhenEmpty)
    }

    @MainActor
    func onBiometricToken(_ enclaveToken: EnclaveToken) {
        passcodeScreenView.isUserInteractionEnabled = false
        completeAuthorization(enclaveToken: enclaveToken)
    }

    @MainActor
    func onBiometricFailure() {
        let alert = alert(
            title: lang("Error"),
            text: lang("Biometric confirmation failed"),
            button: lang("OK"),
            buttonStyle: .default
        )
        super.present(alert, animated: true, completion: nil)
    }

    func passcodeSelected(passcode: String) {
        passcodeScreenView.isUserInteractionEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let enclaveToken: EnclaveToken?
            let unexpectedError: (any Error)?
            do {
                enclaveToken = try await AuthSupport.authorizeWithPasscode(
                    passcode,
                    sessionKind: self.authSessionKind
                )
                unexpectedError = nil
            } catch let error as AuthCooldownError {
                self.showCooldownAlert(error: error)
                enclaveToken = nil
                unexpectedError = nil
            } catch {
                enclaveToken = nil
                unexpectedError = error
            }
            if let enclaveToken {
                completeAuthorization(enclaveToken: enclaveToken)
            } else {
                try? await Task.sleep(for: .seconds(0.2))
                passcodeScreenView.isUserInteractionEnabled = true
                passcodeScreenView.passcodeInputView.currentPasscode = ""
                if let unexpectedError {
                    showAlert(error: unexpectedError)
                } else {
                    passcodeScreenView.wrongPassFeedback()
                    Haptics.play(.error)
                }
            }
        }
    }

    func signOutRequested() {
        guard let onSignOutRequested else { return }
        let text = "\(lang("$logout_all_wallets_warning")) \(lang("$all_secret_words_backup_reminder"))"
            .replacingOccurrences(of: "**", with: "")
        let alert = alert(
            title: lang("Remove Wallets"),
            text: text,
            button: lang("Remove"),
            buttonStyle: .destructive,
            buttonPressed: { [weak self] in
                guard let self else { return }
                self.passcodeScreenView.isUserInteractionEnabled = false
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await onSignOutRequested()
                    } catch {
                        self.passcodeScreenView.isUserInteractionEnabled = true
                        AppActions.showError(error: error)
                    }
                }
            },
            secondaryButton: lang("Cancel"),
            secondaryButtonPressed: nil,
            preferPrimary: true
        )
        super.present(alert, animated: true, completion: nil)
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

    @MainActor
    private func completeAuthorization(enclaveToken: EnclaveToken) {
        animateSuccess()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if successCompletionDelay > 0 {
                try? await Task.sleep(for: .seconds(successCompletionDelay))
            }
            self.onAuthenticated(taskDone: false, enclaveToken: enclaveToken)
        }
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

    func onAuthenticated(taskDone: Bool, enclaveToken: EnclaveToken) {
        navigationItem.setHidesBackButton(true, animated: true)
        Haptics.prepare(.success)
        if taskDone == false && (isBeingDismissed || view.superview == nil || viewStartedDismissing)  {
            return
        }
        if let onAuthTask, taskDone == false {
            authorizationTaskStarted = true
            authorizationNavigationController = navigationController
            wasModalInPresentation = navigationController?.isModalInPresentation ?? false
            wasBackSwipeToDismissAllowed = navigationController?.isBackSwipeToDismissAllowed ?? true
            authorizationNavigationController?.allowBackSwipeToDismiss(false)
            authorizationNavigationController?.isModalInPresentation = true
            navigationItem.rightBarButtonItem?.isEnabled = false
            onAuthTask(enclaveToken) {
                DispatchQueue.main.async { [weak self] in
                    self?.onAuthenticated(taskDone: true, enclaveToken: enclaveToken)
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
                        self?.onDoneCallback?(enclaveToken)
                        self?.onDoneCallback = nil
                    })
                }
            } else {
                self.onDoneCallback?(enclaveToken)
                self.onDoneCallback = nil
            }
        } else {
            if customHeaderVC != nil {
                self.onDoneCallback?(enclaveToken)
                self.onDoneCallback = nil
            } else {
                dismiss(animated: true) { [weak self] in
                    self?.onDoneCallback?(enclaveToken)
                    self?.onDoneCallback = nil
                }
            }
        }
    }
}
