import UIKit
import UIComponents
import WalletContext
import WalletCore

/// How the consent sheet comes up over a screen and goes: UIKit's presentation. A test run without a window scene, where
/// UIKit never finishes bringing a sheet up or taking it away, puts in its place one whose transitions it finishes.
@MainActor
class AgentConsentSheetPresentation {
    static var current = AgentConsentSheetPresentation()

    /// What `presenter` shows over itself, the consent sheet or anything else
    func presentedViewController(of presenter: UIViewController) -> UIViewController? {
        presenter.presentedViewController
    }

    func present(_ sheet: UIViewController, over presenter: UIViewController) {
        presenter.present(sheet, animated: true)
    }

    /// `sheet` is shown, or coming up
    func isPresented(_ sheet: UIViewController) -> Bool {
        sheet.presentingViewController != nil
    }

    /// Runs `action` once `sheet` is up, if it is still coming up, and returns true; false when it is up already
    func whenPresented(_ sheet: UIViewController, _ action: @escaping () -> Void) -> Bool {
        guard sheet.isBeingPresented, let transition = sheet.transitionCoordinator else { return false }
        return transition.animate(alongsideTransition: nil) { _ in action() }
    }

    /// Takes `sheet` away, then runs `completion`
    func dismiss(_ sheet: UIViewController, animated: Bool, completion: @escaping () -> Void) {
        sheet.dismiss(animated: animated, completion: completion)
    }
}

/// Asks for the Agent's consent at the first action that would send something to the Agent: a message, a hint, a
/// recording, or a chat opened from elsewhere
@MainActor
enum AgentConsentPrompt {
    /// Runs `action` once the Agent has the user's consent: at once when `isGiven` or `load` finds it, or once the user
    /// allows it in the consent sheet over `presenter` and `accept` records it. `onGiven` runs first whenever consent
    /// turns out to be given. Closing the sheet runs only `onCancel`, so nothing is sent and the next action asks again.
    static func run(
        from presenter: UIViewController,
        isGiven: Bool,
        load: @escaping () async throws -> Bool,
        accept: @escaping () async throws -> Void,
        onGiven: @escaping @MainActor () -> Void = {},
        onCancel: @escaping @MainActor () -> Void = {},
        action: @escaping @MainActor () -> Void
    ) {
        guard !isGiven else {
            action()
            return
        }
        Task { @MainActor [weak presenter] in
            // A failed lookup asks, as accepting again only records consent again
            let isAllowed = (try? await load()) == true
            if isAllowed {
                onGiven()
                action()
                return
            }
            guard let presenter else { return }
            present(from: presenter, accept: accept, onCancel: onCancel) {
                onGiven()
                action()
            }
        }
    }

    /// Shows the consent sheet over `presenter`. Allow runs `accept`, closes the sheet and then runs `onAllow`; without
    /// `accept`, Allow closes the sheet and runs `onAllow` at once. A failed `accept` keeps the sheet and goes to
    /// `onError`. Returns whether the sheet came up: UIKit turns a presentation down while the presenter is in another
    /// transition, and then neither `onAllow` nor `onCancel` runs.
    @discardableResult
    static func present(
        from presenter: UIViewController,
        accept: (() async throws -> Void)?,
        onError: @escaping @MainActor (DisplayError) -> Void = { AppActions.showError(error: $0) },
        onCancel: @escaping @MainActor () -> Void,
        onAllow: @escaping @MainActor () -> Void
    ) -> Bool {
        // A sheet already up, of consent or anything else, keeps the screen; the action waits for the next try
        let presentation = AgentConsentSheetPresentation.current
        guard presentation.presentedViewController(of: presenter) == nil, presenter.view.window != nil else {
            onCancel()
            return false
        }
        // The keyboard would cover Allow; a typed message stays in its field
        presenter.view.window?.endEditing(true)
        let sheet = AgentConsentSheetVC(accept: accept, onError: onError, onAllow: onAllow, onCancel: onCancel)
        let navigation = WNavigationController(rootViewController: sheet)
        presentation.present(navigation, over: presenter)
        return presentation.isPresented(navigation)
    }
}

/// The Agent's consent in a bottom sheet sized to its content up to the screen, where it scrolls above Allow, under
/// the header the app's sheets have: the Agent's name and a close button. Closing it by the close button, a swipe down,
/// a tap outside or Escape cancels.
@MainActor
final class AgentConsentSheetVC: UIViewController, UISheetPresentationControllerDelegate {
    let consentView = AgentConsentView()
    private let accept: (() async throws -> Void)?
    private let onError: @MainActor (DisplayError) -> Void
    private let onAllow: @MainActor () -> Void
    private let onCancel: @MainActor () -> Void
    private var acceptTask: Task<Void, Never>?
    private var isFinished = false
    /// The sheet's detent: as tall as the content and Allow's area, over the bottom safe area, up to the screen
    private(set) var sheetHeight: CGFloat = 560

    init(
        accept: (() async throws -> Void)?,
        onError: @escaping @MainActor (DisplayError) -> Void,
        onAllow: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.accept = accept
        self.onError = onError
        self.onAllow = onAllow
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        acceptTask?.cancel()
    }

    /// The presented sheet: the navigation controller that shows the header
    private var sheetController: UIViewController {
        navigationController ?? self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Agent")
        navigationItem.titleView = Self.makeTitleView()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.cancel()
        })
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "nav_close"
        view.backgroundColor = UIColor.air.background
        consentView.translatesAutoresizingMaskIntoConstraints = false
        consentView.onContinue = { [weak self] in self?.allow() }
        consentView.onLearnMore = {
            guard let url = URL(string: APP_PRIVACY_POLICY_URL) else { return }
            AppActions.openInBrowser(url, title: lang("Privacy Policy"), injectDappConnect: false)
        }
        view.addSubview(consentView)
        NSLayoutConstraint.activate([
            consentView.topAnchor.constraint(equalTo: view.topAnchor),
            consentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            consentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            consentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        if let sheet = sheetController.sheetPresentationController {
            sheet.delegate = self
            sheet.detents = [.custom(identifier: .init("agentConsent")) { [weak self] context in
                min(self?.sheetHeight ?? 560, context.maximumDetentValue)
            }]
        }
        // Text of another size makes the content another height, which the sheet follows
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: AgentConsentSheetVC, _) in
                controller.view.setNeedsLayout()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0) {
            guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
            view.setNeedsLayout()
        }
    }

    /// The Agent's name with its spinning top beside it, as the typing row has it beside its step, the pair in the
    /// middle of the header. The top spins as it does there and grows while held as every top does: its canvas goes up
    /// into the window, over the header and the sheet, and the name stays where it is.
    private static func makeTitleView() -> UIView {
        let top = AgentSpinningTopView()
        top.isAccessibilityElement = false
        top.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            top.widthAnchor.constraint(equalToConstant: AgentTypingIndicatorCell.spinningTopSize),
            top.heightAnchor.constraint(equalToConstant: AgentTypingIndicatorCell.spinningTopSize),
        ])
        // The app's sheets' title, as Import Wallet's and Add Wallet's headers have it
        let label = NavigationHeader2.makeTitleLabel(lang("Agent"))
        label.accessibilityTraits = .header
        let stack = UIStackView(arrangedSubviews: [top, label])
        // Sized by its content, which the navigation bar lays out
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        return stack
    }

    /// The height depends on the safe area, which can change without the view's bounds
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    /// Keeps the sheet as tall as its content, so the content scrolls only when the screen has no room for all of it
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard consentView.bounds.width > 0 else { return }
        consentView.layoutIfNeeded()
        // Detents add the bottom safe area themselves, which Allow's area already holds. Rounded up to the pixel, and
        // followed however little it changes, so the sheet is never a fraction short of its content, which would
        // leave the content that much to scroll.
        let scale = max(1, traitCollection.displayScale)
        let height = ((consentView.fittingHeight - view.safeAreaInsets.bottom) * scale).rounded(.up) / scale
        guard height != sheetHeight else { return }
        sheetHeight = height
        sheetController.sheetPresentationController?.invalidateDetents()
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancel))]
    }

    override func accessibilityPerformEscape() -> Bool {
        cancel()
        return true
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finishCancelled()
    }

    @objc private func cancel() {
        guard acceptTask == nil, !isFinished else { return }
        dismissSheet { self.finishCancelled() }
    }

    /// Closes the sheet, then runs `completion`. UIKit drops a dismissal asked for while the sheet is still coming up,
    /// so a close or Allow that quick waits for the sheet to be up.
    private func dismissSheet(completion: @escaping () -> Void) {
        let sheet = sheetController
        let presentation = AgentConsentSheetPresentation.current
        guard presentation.isPresented(sheet) else {
            completion()
            return
        }
        if presentation.whenPresented(sheet, {
            DispatchQueue.main.async { self.dismissSheet(completion: completion) }
        }) {
            return
        }
        presentation.dismiss(sheet, animated: true, completion: completion)
    }

    private func finishCancelled() {
        guard !isFinished else { return }
        isFinished = true
        onCancel()
    }

    private func allow() {
        guard acceptTask == nil, !isFinished else { return }
        guard let accept else {
            finishAllowed()
            return
        }
        consentView.isUserInteractionEnabled = false
        navigationItem.rightBarButtonItem?.isEnabled = false
        sheetController.isModalInPresentation = true
        acceptTask = Task { [weak self] in
            do {
                try await accept()
                guard let self, !Task.isCancelled else { return }
                self.finishAllowed()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.acceptTask = nil
                self.consentView.isUserInteractionEnabled = true
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                self.sheetController.isModalInPresentation = false
                if let displayError = AgentV2Copy.displayError(error) {
                    self.onError(displayError)
                }
            }
        }
    }

    /// Closes the sheet and carries out the action that asked, once the sheet is gone
    private func finishAllowed() {
        guard !isFinished else { return }
        isFinished = true
        let onAllow = self.onAllow
        dismissSheet { onAllow() }
    }
}
