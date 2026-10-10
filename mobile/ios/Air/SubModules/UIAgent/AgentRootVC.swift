import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
final class AgentRootVC: WViewController {
    private let client: AgentV2Client
    private let preloader: AgentPreloader?
    private let showConsentError: () -> Void
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let consentView = AgentConsentView()
    private var transitionTask: Task<Void, Never>?
    private var preparingModel: AgentV2Model?
    private var isTransferringPendingRequest = false

    init(
        client: AgentV2Client = LiveAgentV2Client(),
        preloader: AgentPreloader? = nil,
        showConsentError: @escaping () -> Void = {
            AppActions.showError(error: DisplayError(text: lang("Agent is unavailable")))
        }
    ) {
        self.client = client
        self.preloader = preloader
        self.showConsentError = showConsentError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        transitionTask?.cancel()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !isTransferringPendingRequest,
              isMovingFromParent || parent?.isMovingFromParent == true
                || isBeingDismissed || navigationController?.isBeingDismissed == true else {
            return
        }
        cancelPreparation()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil, !isTransferringPendingRequest {
            cancelPreparation()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Agent")
        view.backgroundColor = .air.background
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadConsent()
    }

    override func scrollToTop(animated: Bool) {
        consentView.scrollToTop(animated: animated)
    }

    private func loadConsent() {
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            guard let self else { return }
            let hasConsent = (try? await self.client.consent()) == true
            guard !Task.isCancelled else { return }
            if hasConsent {
                await self.showAgent()
            } else {
                self.showConsent()
            }
            self.transitionTask = nil
        }
    }

    private func showConsent() {
        activityIndicator.stopAnimating()
        consentView.translatesAutoresizingMaskIntoConstraints = false
        consentView.onLearnMore = {
            guard let url = URL(string: APP_PRIVACY_POLICY_URL) else { return }
            AppActions.openInBrowser(url, title: lang("Privacy Policy"), injectDappConnect: false)
        }
        consentView.onContinue = { [weak self] in self?.acceptConsent() }
        view.addSubview(consentView)
        NSLayoutConstraint.activate([
            consentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            consentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            consentView.topAnchor.constraint(equalTo: view.topAnchor),
            consentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func acceptConsent() {
        guard transitionTask == nil else { return }
        consentView.isUserInteractionEnabled = false
        transitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.acceptConsent()
                guard !Task.isCancelled else { return }
                await self.showAgent()
                self.transitionTask = nil
            } catch {
                self.transitionTask = nil
                self.consentView.isUserInteractionEnabled = true
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.showConsentError()
            }
        }
    }

    private func showAgent() async {
        consentView.removeFromSuperview()
        activityIndicator.startAnimating()
        let model: AgentV2Model
        if let preloader {
            guard let preparedModel = await preloader.acquireModel() else { return }
            model = preparedModel
        } else {
            model = AgentV2Model(client: client)
        }
        preparingModel = model
        await model.waitForInitialLoad()
        guard !Task.isCancelled else {
            model.stop()
            return
        }
        guard let navigationController,
              let index = navigationController.viewControllers.firstIndex(of: self) else {
            model.stop()
            preparingModel = nil
            return
        }
        preparingModel = nil
        isTransferringPendingRequest = true
        var viewControllers = navigationController.viewControllers
        viewControllers[index] = AgentVC(model: model)
        navigationController.setViewControllers(viewControllers, animated: false)
    }

    private func cancelPreparation() {
        transitionTask?.cancel()
        transitionTask = nil
        preparingModel?.stop()
        preparingModel = nil
        AgentEntryPoint.clearPendingRequest()
    }
}
