import UIKit
import UIComponents
import WalletCore
import WalletContext
import WalletCoreTypes

private let log = Log("WalletConnectPay")

@MainActor
final class WalletConnectPayFlow: WalletCoreData.EventsObserver {
    static let shared = WalletConnectPayFlow()

    private enum StepKind: Hashable {
        case loading
        case optionSelection
        case signTransaction
        case signData
        case dataCollection
        case status
    }

    private enum NavigationStrategy {
        case automatic
        case replaceAll
        case replaceTopCrossfade
    }

    private weak var navigationController: WNavigationController?
    private weak var optionSelectionVC: WalletConnectPayOptionSelectionVC?
    private weak var paymentStatusVC: WalletConnectPayPaymentStatusVC?
    private var loadingDismissTask: Task<Void, Never>?
    private var completedStepKinds: Set<StepKind> = []
    private var shouldIgnoreStatusUpdates = false
    private var isObserving = false
    private var latestPaymentContext: WalletConnectPayPaymentContext?

    private init() {}

    func start() {
        guard !isObserving else { return }
        isObserving = true
        WalletCoreData.add(eventObserver: self)
    }

    nonisolated func walletCore(event: WalletCoreData.Event) {
        Task {
            await self.handle(event: event)
        }
    }

    private func handle(event: WalletCoreData.Event) async {
        switch event {
        case .walletConnectPayLoading(let update):
            await showLoading(update)
        case .walletConnectPayCloseLoading:
            closeLoadingIfVisible()
        case .walletConnectPaySignTransaction(let update):
            await showSignTransaction(update)
        case .walletConnectPaySignTransactionComplete:
            markComplete(.signTransaction)
        case .walletConnectPaySignData(let update):
            await showSignData(update)
        case .walletConnectPaySignDataComplete:
            markComplete(.signData)
        case .walletConnectPayDataCollection(let update):
            showDataCollection(update)
        case .walletConnectPayDataCollectionComplete:
            markComplete(.dataCollection)
        case .walletConnectPayOptionSelection(let update):
            showOptionSelection(update)
        case .walletConnectPayOptionSelectionComplete:
            markComplete(.optionSelection)
        case .walletConnectPayProcessing(let update):
            await showProcessing(update)
        case .walletConnectPayPaymentComplete(let update):
            await showPaymentComplete(update)
        default:
            break
        }
    }

    private func showLoading(_ update: ApiUpdate.WalletConnectPayLoading) async {
        shouldIgnoreStatusUpdates = false
        latestPaymentContext = nil
        await switchAccountIfNeeded(accountId: update.accountId)
        guard activeNavigationController == nil else { return }

        let vc = WalletConnectPayLoadingVC(onCancel: { [weak self] in
            self?.dismissUserClosedFlow()
        })
        showStep(.loading, viewController: vc)
    }

    private func closeLoadingIfVisible() {
        guard let navigationController = activeNavigationController else { return }
        guard let top = navigationController.viewControllers.last else { return }

        if top is WalletConnectPayLoadingVC {
            scheduleCompletedLoadingDismiss()
            return
        }

        if let status = top as? WalletConnectPayPaymentStatusVC, status.isComplete {
            return
        }

        dismissFlow()
    }

    private func scheduleCompletedLoadingDismiss() {
        markComplete(.loading)
        loadingDismissTask?.cancel()
        loadingDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.dismissCompletedLoadingIfStillVisible()
        }
    }

    private func dismissCompletedLoadingIfStillVisible() {
        guard completedStepKinds.contains(.loading),
              activeNavigationController?.viewControllers.last is WalletConnectPayLoadingVC else {
            return
        }
        dismissFlow()
    }

    private func showOptionSelection(_ update: ApiUpdate.WalletConnectPayOptionSelection) {
        shouldIgnoreStatusUpdates = false
        if let optionSelectionVC,
           activeNavigationController?.viewControllers.contains(optionSelectionVC) == true,
           !completedStepKinds.contains(.optionSelection) {
            optionSelectionVC.update(update)
            return
        }

        let vc = WalletConnectPayOptionSelectionVC(
            update: update,
            onSelect: { [weak self] optionId, update in
                self?.confirmOptionSelection(promiseId: update.promiseId, optionId: optionId)
            },
            onSwitchAccount: { [weak self] accountId, update in
                self?.switchOptionSelectionAccount(accountId: accountId, update: update)
            },
            onCancel: { [weak self] update in
                self?.cancelAndDismiss(promiseId: update.promiseId)
            }
        )
        optionSelectionVC = vc
        showStep(.optionSelection, viewController: vc)
    }

    private func showSignTransaction(_ update: ApiUpdate.WalletConnectPaySignTransaction) async {
        shouldIgnoreStatusUpdates = false
        latestPaymentContext = WalletConnectPayPaymentContext(
            paymentInfo: update.paymentInfo,
            paymentOption: update.paymentOption
        )
        await switchAccountIfNeeded(accountId: update.accountId)

        let vc = WalletConnectPaySignTransactionVC(
            request: update,
            onSubmit: { [weak self] request, password in
                guard let self else { throw CancellationError() }
                return try await self.submitSignTransaction(request: request, password: password)
            },
            onCancel: { [weak self] in
                self?.cancelAndDismiss(promiseId: update.promiseId)
            }
        )
        showStep(.signTransaction, viewController: vc)
    }

    private func showSignData(_ update: ApiUpdate.WalletConnectPaySignData) async {
        shouldIgnoreStatusUpdates = false
        latestPaymentContext = WalletConnectPayPaymentContext(
            paymentInfo: update.paymentInfo,
            paymentOption: update.paymentOption
        )
        await switchAccountIfNeeded(accountId: update.accountId)

        let vc = WalletConnectPaySignDataVC(
            update: update,
            onSubmit: { [weak self] update, password in
                guard let self else { throw CancellationError() }
                return try await self.submitSignData(update: update, password: password)
            },
            onCancel: { [weak self] in
                self?.cancelAndDismiss(promiseId: update.promiseId)
            }
        )
        showStep(.signData, viewController: vc)
    }

    private func showDataCollection(_ update: ApiUpdate.WalletConnectPayDataCollection) {
        shouldIgnoreStatusUpdates = false
        guard let vc = WalletConnectPayDataCollectionVC(
            update: update,
            onComplete: { [weak self] in
                self?.completeDataCollection(promiseId: update.promiseId)
            },
            onCancel: { [weak self] in
                self?.cancelAndDismiss(promiseId: update.promiseId)
            },
            onError: { [weak self] error in
                if error != walletConnectPayUserCancelReason {
                    AppActions.showError(error: DisplayError(text: error))
                }
                self?.cancelAndDismiss(promiseId: update.promiseId)
            }
        ) else {
            AppActions.showError(error: DisplayError(text: lang("Cannot load widget")))
            cancelAndDismiss(promiseId: update.promiseId)
            return
        }

        showStep(.dataCollection, viewController: vc)
    }

    private func showProcessing(_ update: ApiUpdate.WalletConnectPayProcessing) async {
        guard !shouldIgnoreStatusUpdates else { return }
        await switchAccountIfNeeded(accountId: update.accountId)

        if activeNavigationController?.viewControllers.contains(where: { $0 === paymentStatusVC }) == true {
            return
        }

        let vc = WalletConnectPayPaymentStatusVC(
            processing: update,
            paymentContext: latestPaymentContext,
            onClose: { [weak self] in
                self?.dismissUserClosedFlow()
            }
        )
        paymentStatusVC = vc
        showStep(
            .status,
            viewController: vc,
            strategy: .replaceTopCrossfade
        )
    }

    private func showPaymentComplete(_ update: ApiUpdate.WalletConnectPayPaymentComplete) async {
        guard !shouldIgnoreStatusUpdates else { return }
        await switchAccountIfNeeded(accountId: update.accountId)

        if let paymentStatusVC,
           activeNavigationController?.viewControllers.contains(paymentStatusVC) == true {
            paymentStatusVC.update(
                complete: update,
                paymentContext: latestPaymentContext
            )
            completedStepKinds.remove(.status)
            return
        }

        let vc = WalletConnectPayPaymentStatusVC(
            complete: update,
            paymentContext: latestPaymentContext,
            onClose: { [weak self] in
                self?.dismissUserClosedFlow()
            }
        )
        paymentStatusVC = vc
        showStep(
            .status,
            viewController: vc,
            strategy: .replaceTopCrossfade
        )
        Haptics.play(.success)
    }

    private func showStep(
        _ kind: StepKind,
        viewController: UIViewController,
        detents: [UISheetPresentationController.Detent] = [.large()],
        strategy: NavigationStrategy = .automatic
    ) {
        if kind != .loading {
            loadingDismissTask?.cancel()
            loadingDismissTask = nil
        }
        completedStepKinds.remove(kind)

        guard let navigationController = activeNavigationController else {
            completedStepKinds.removeAll()
            let navigationController = WNavigationController(rootViewController: viewController)
            configureSheet(navigationController, detents: detents)
            self.navigationController = navigationController
            topViewController()?.present(navigationController, animated: true)
            return
        }

        if strategy == .replaceTopCrossfade {
            (viewController as? WalletConnectPayPaymentStatusVC)?.prepareForReplacementTransition()
            let coordinator = ContentReplaceAnimationCoordinator()
            coordinator.replaceNavigationTop(with: viewController, in: navigationController) {
                (viewController as? WalletConnectPayPaymentStatusVC)?.animateToContentHeight()
            }
            return
        }

        configureSheet(navigationController, detents: detents)

        if strategy == .replaceAll {
            navigationController.setViewControllers([viewController], animated: true)
            return
        }

        guard let top = navigationController.viewControllers.last,
              let topKind = stepKind(for: top) else {
            navigationController.setViewControllers([viewController], animated: true)
            return
        }

        if topKind == kind || topKind == .loading || completedStepKinds.contains(topKind) {
            var stack = navigationController.viewControllers
            stack.removeLast()
            stack.append(viewController)
            navigationController.setViewControllers(stack, animated: true)
        } else {
            navigationController.pushViewController(viewController, animated: true)
        }
    }

    private var activeNavigationController: WNavigationController? {
        guard let navigationController,
              navigationController.presentingViewController != nil || navigationController.view.window != nil else {
            return nil
        }
        return navigationController
    }

    private func configureSheet(_ navigationController: WNavigationController, detents: [UISheetPresentationController.Detent]) {
        navigationController.isModalInPresentation = false
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = detents
        }
    }

    private func stepKind(for viewController: UIViewController) -> StepKind? {
        switch viewController {
        case is WalletConnectPayLoadingVC:
            .loading
        case is WalletConnectPayOptionSelectionVC:
            .optionSelection
        case is WalletConnectPaySignTransactionVC:
            .signTransaction
        case is WalletConnectPaySignDataVC:
            .signData
        case is WalletConnectPayDataCollectionVC:
            .dataCollection
        case is WalletConnectPayPaymentStatusVC:
            .status
        default:
            nil
        }
    }

    private func markComplete(_ kind: StepKind) {
        completedStepKinds.insert(kind)
        switch kind {
        case .optionSelection:
            optionSelectionVC = nil
        case .status:
            paymentStatusVC = nil
        default:
            break
        }
    }

    private func switchOptionSelectionAccount(
        accountId: String,
        update: ApiUpdate.WalletConnectPayOptionSelection
    ) {
        guard accountId != update.accountId else { return }

        optionSelectionVC?.setLoading(accountId: accountId)

        Task {
            do {
                _ = try await AccountStore.activateAccount(accountId: accountId)
                try await Api.refreshWalletConnectPayOptionSelection(
                    paymentLink: update.paymentLink,
                    accountId: accountId,
                    promiseId: update.promiseId
                )
            } catch {
                log.error("switchOptionSelectionAccount failed: \(error, .public)")
                optionSelectionVC?.update(update)
                AppActions.showError(error: error)
            }
        }
    }

    private func confirmOptionSelection(promiseId: String, optionId: String) {
        completedStepKinds.insert(.optionSelection)
        Task {
            do {
                try await Api.confirmWalletConnectPayOptionSelection(promiseId: promiseId, optionId: optionId)
            } catch {
                log.error("confirmOptionSelection failed: \(error, .public)")
                completedStepKinds.remove(.optionSelection)
                optionSelectionVC?.stopLoading()
                AppActions.showError(error: error)
            }
        }
    }

    private func completeDataCollection(promiseId: String) {
        completedStepKinds.insert(.dataCollection)
        Task {
            do {
                try await Api.completeWalletConnectPayDataCollection(promiseId: promiseId)
            } catch {
                log.error("completeDataCollection failed: \(error, .public)")
                completedStepKinds.remove(.dataCollection)
                AppActions.showError(error: error)
                cancelAndDismiss(promiseId: promiseId, reason: error.localizedDescription)
            }
        }
    }

    private func cancelAndDismiss(promiseId: String, reason: String? = walletConnectPayUserCancelReason) {
        shouldIgnoreStatusUpdates = true
        dismissFlow()

        Task {
            do {
                try await Api.cancelWalletConnectPay(promiseId: promiseId, reason: reason)
            } catch {
                log.error("cancelWalletConnectPay failed: \(error, .public)")
            }
        }
    }

    private func dismissUserClosedFlow() {
        shouldIgnoreStatusUpdates = true
        dismissFlow()
    }

    private func dismissFlow(animated: Bool = true, completion: (() -> Void)? = nil) {
        let navigationController = activeNavigationController
        self.navigationController = nil
        optionSelectionVC = nil
        paymentStatusVC = nil
        latestPaymentContext = nil
        loadingDismissTask?.cancel()
        loadingDismissTask = nil
        completedStepKinds.removeAll()
        if let navigationController {
            navigationController.isModalInPresentation = false
            navigationController.viewControllers.forEach { $0.isModalInPresentation = false }
            navigationController.dismiss(animated: animated, completion: completion)
        } else {
            completion?()
        }
    }

    private func switchAccountIfNeeded(accountId: String) async {
        do {
            if AccountStore.accountId != accountId {
                _ = try await AccountStore.activateAccount(accountId: accountId)
            }
        } catch {
            log.fault("failed to switch to account \(accountId, .public) error:\(error, .public)")
        }
    }

    private func submitSignTransaction(
        request: ApiUpdate.WalletConnectPaySignTransaction,
        password: String?
    ) async throws -> ApiSignDappTransfersResult {
        let account = AccountStore.get(accountId: request.accountId)
        let chain = request.operationChain
        let address = account.getAddress(chain: chain) ?? ""
        let dappChain = ApiDappSessionChain(
            chain: chain,
            address: address,
            network: account.network
        )
        let result = try await Api.signDappTransfersProtected(
            dappChain: dappChain,
            accountId: request.accountId,
            messages: request.transactions.map { ApiTransferToSign($0, chain: chain) },
            options: .init(
                password: password,
                vestingAddress: nil,
                validUntil: request.validUntil,
                isLegacyOutput: request.isLegacyOutput ?? request.isSignOnly
            )
        )
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        if result.mfaRequestHash != nil {
            throw DisplayError(text: "Telegram confirmation is not supported for WalletConnect Pay.")
        }
        guard let signedTransfers = result.signedTransfers else {
            throw SdkError.unexpected(message: "Missing signed WalletConnect Pay transfers", context: result)
        }
        try await Api.confirmWalletConnectPaySignTransaction(
            promiseId: request.promiseId,
            data: signedTransfers
        )
        completedStepKinds.insert(.signTransaction)
        return result
    }

    private func submitSignData(
        update: ApiUpdate.WalletConnectPaySignData,
        password: String?
    ) async throws -> ApiMfaProtectedResult {
        let account = AccountStore.get(accountId: update.accountId)
        let address = account.getAddress(chain: update.operationChain) ?? ""
        let dappChain = ApiDappSessionChain(
            chain: update.operationChain,
            address: address,
            network: account.network
        )
        let result = try await Api.signDappData(
            dappChain: dappChain,
            accountId: update.accountId,
            dappUrl: walletConnectPaySignUrl,
            payloadToSign: update.payloadToSign,
            password: password
        )
        try await Api.confirmWalletConnectPaySignData(
            promiseId: update.promiseId,
            data: AnyEncodable(result)
        )
        completedStepKinds.insert(.signData)
        return ApiMfaProtectedResult()
    }
}
