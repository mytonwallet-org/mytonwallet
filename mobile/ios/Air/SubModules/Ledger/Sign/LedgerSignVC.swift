import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
public enum LedgerSignCancellationReason: Sendable {
    case dismissed
    case cancelButton
    case closeButton
    case taskCancelled
}

@MainActor
public enum LedgerSignEvent<Payload: Sendable> {
    case submissionStarted
    case retryableFailure(any Error)
    case cancellationRequested(LedgerSignCancellationReason)
    case resolved(ActionSubmissionResult<Payload>)
    case cancelled(LedgerSignCancellationReason)
}

@MainActor
public final class LedgerSignVC<HeaderView: View, Payload: Sendable>: WViewController {
    public var onEvent: ((LedgerSignVC<HeaderView, Payload>, LedgerSignEvent<Payload>) -> Void)?

    private let headerView: HeaderView
    private let compactHeaderView: AnyView
    private let model: LedgerSignModel<Payload>
    private var hostingController: UIHostingController<LedgerSignView<HeaderView>>?
    private var didResolve = false
    private var isLeaving = false
    private var cancellationReason: LedgerSignCancellationReason?
    private weak var commitNavigationController: UINavigationController?
    private var wasModalInPresentation = false
    private var wasBackSwipeToDismissAllowed = true
    private var wasBackButtonHidden = false

    public init(
        model: LedgerSignModel<Payload>,
        title: String?,
        headerView: HeaderView,
        compactHeaderView: AnyView
    ) {
        self.model = model
        self.headerView = headerView
        self.compactHeaderView = compactHeaderView
        super.init(nibName: nil, bundle: nil)
        self.title = title ?? lang("Confirm via Ledger")
        model.onSubmissionStateChange = { [weak self] state in
            self?.handleSubmissionState(state)
        }
        model.onCancel = { [weak self] in
            self?.handleCancellationRequest(reason: .cancelButton)
        }
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        if isPresentationModal {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .close,
                primaryAction: UIAction { [weak self] _ in
                    self?.handleCancellationRequest(reason: .closeButton)
                }
            )
        }
        hostingController = addHostingController(
            LedgerSignView(
                headerView: headerView,
                compactHeaderView: compactHeaderView,
                viewModel: model.viewModel
            ),
            constraints: .fill
        )
        view.backgroundColor = .air.sheetBackground
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isLeaving = false
        model.start()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !didResolve {
            isLeaving = true
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        restoreDismissalControls()
        guard !didResolve else { return }
        if let result = model.safetyResult {
            notifyCancellationRequested(.dismissed)
            resolve(.resolved(result))
        } else if model.isSubmitting {
            notifyCancellationRequested(.dismissed)
        } else {
            resolve(.cancelled(.dismissed))
        }
    }

    public func requestCancellation(reason: LedgerSignCancellationReason) {
        handleCancellationRequest(reason: reason)
    }

    private func handleSubmissionState(_ state: LedgerSignSubmissionState<Payload>) {
        guard !didResolve else { return }
        switch state {
        case .idle:
            unlockDismissal()
        case .submitting:
            lockDismissal()
            onEvent?(self, .submissionStarted)
        case .retryableFailure(let error):
            unlockDismissal()
            onEvent?(self, .retryableFailure(error))
            if let cancellationReason, isLeaving {
                resolve(.cancelled(cancellationReason))
            }
        case .partiallyCommitted(let receipt, let remainingWork):
            unlockDismissal()
            if cancellationReason != nil || isLeaving {
                resolve(.resolved(.partiallyCommitted(receipt: receipt, remainingWork: remainingWork)))
            }
        case .resolved(let result):
            resolve(.resolved(result))
        }
    }

    private func handleCancellationRequest(reason: LedgerSignCancellationReason) {
        guard !didResolve else { return }
        if let result = model.safetyResult {
            notifyCancellationRequested(reason)
            resolve(.resolved(result))
            return
        }
        guard model.allowsCancellation else {
            if model.isSubmitting {
                notifyCancellationRequested(reason)
            }
            return
        }
        model.cancel()
        resolve(.cancelled(reason))
        if canGoBack {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func notifyCancellationRequested(_ reason: LedgerSignCancellationReason) {
        guard cancellationReason == nil else { return }
        cancellationReason = reason
        onEvent?(self, .cancellationRequested(reason))
    }

    private func resolve(_ event: LedgerSignEvent<Payload>) {
        guard !didResolve else { return }
        didResolve = true
        onEvent?(self, event)
    }

    private func lockDismissal() {
        model.viewModel.backEnabled = false
        guard commitNavigationController == nil else { return }
        commitNavigationController = navigationController
        wasModalInPresentation = navigationController?.isModalInPresentation ?? false
        wasBackSwipeToDismissAllowed = navigationController?.isBackSwipeToDismissAllowed ?? true
        wasBackButtonHidden = navigationItem.hidesBackButton
        commitNavigationController?.allowBackSwipeToDismiss(false)
        commitNavigationController?.isModalInPresentation = true
        navigationItem.setHidesBackButton(true, animated: false)
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    private func unlockDismissal() {
        model.viewModel.backEnabled = model.allowsCancellation
        restoreDismissalControls()
        navigationItem.rightBarButtonItem?.isEnabled = true
    }

    private func restoreDismissalControls() {
        commitNavigationController?.allowBackSwipeToDismiss(wasBackSwipeToDismissAllowed)
        commitNavigationController?.isModalInPresentation = wasModalInPresentation
        commitNavigationController = nil
        navigationItem.setHidesBackButton(wasBackButtonHidden, animated: false)
    }
}
