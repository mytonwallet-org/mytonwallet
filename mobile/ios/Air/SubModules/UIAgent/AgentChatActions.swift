import UIKit
import WalletContext
import WalletCore

@MainActor
final class AgentChatActions {
    private let model: AgentModel
    private static let problemReportCommentMaxLength = 1000

    private weak var viewController: UIViewController?
    private let cancelDictation: () -> Void
    private let refreshNavigationItemMenu: () -> Void
    private let showError: (DisplayError) -> Void
    private let showToast: (String) -> Void
    /// Shows the support sheet over the screen
    private let presentConfirmation: (UIAlertController, UIViewController) -> Void
    /// The user confirmed deletion, so the screen closes before server cleanup finishes.
    private(set) var isDeletingChat = false
    /// The support sheet on screen, whose Call follows `canConfirmSupportRequest`
    private weak var supportConfirmation: UIAlertController?
    private var canConfirmSupportRequest: () -> Bool = { false }

    init(
        model: AgentModel,
        viewController: UIViewController,
        cancelDictation: @escaping () -> Void,
        refreshNavigationItemMenu: @escaping () -> Void,
        showError: @escaping (DisplayError) -> Void = { AppActions.showError(error: $0) },
        showToast: @escaping (String) -> Void = { AppActions.showToast(message: $0) },
        presentConfirmation: @escaping (UIAlertController, UIViewController) -> Void = { $1.present($0, animated: true) }
    ) {
        self.model = model
        self.viewController = viewController
        self.cancelDictation = cancelDictation
        self.refreshNavigationItemMenu = refreshNavigationItemMenu
        self.showError = showError
        self.showToast = showToast
        self.presentConfirmation = presentConfirmation
    }

    /// A news discussion the user hasn't written in has no Delete: the chat list leaves it out, and it has nothing of
    /// the user's to delete
    var canDeleteChat: Bool {
        guard !isDeletingChat, let model = model as? AgentV2Model else { return false }
        return model.canDeleteChat && model.isStarted
    }

    /// A chat whose thread is on its way: it has its question or its news post, or is opening. A news discussion the
    /// user hasn't written in has its menu only once there is something in it.
    var willHaveMenu: Bool {
        if isDeletingChat { return true }
        guard let model = model as? AgentV2Model, model.isStarted else { return false }
        return model.hasMessages || model.isOpening || model.threadId != nil
    }

    func makeNavigationOverflowMenu() -> UIMenu {
        UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            self?.cancelDictation()
            completion(self?.makeOverflowMenu().children ?? [])
        }])
    }

    func makeOverflowMenu() -> UIMenu {
        var children: [UIMenuElement] = []
        if model.canReportProblem {
            children.append(UIAction(title: lang("Report a Problem"), image: UIImage(systemName: "flag")) { [weak self] _ in
                self?.reportProblem(messageID: nil)
            })
        }
        if canDeleteChat {
            children.append(UIAction(
                title: lang("Delete Chat"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmChatDeletion()
            })
        }
        return UIMenu(children: children)
    }

    /// Contact Support from the header's headset: the sheet asks, and Call sends the request
    func confirmHeaderSupportRequest() {
        guard model.canRequestSupport else { return }
        presentSupportConfirmation(canConfirm: { [weak model] in model?.canRequestSupport == true }) { [weak model] in
            model?.requestSupport(source: .header)
        }
    }

    /// Contact Support among the starter hints: after the sheet, the chat support has takes the request through
    /// `openThread`, or this chat asks, unless `hasStayedOnScreen` finds the chat left by then
    func confirmStarterHintSupportRequest(
        hasStayedOnScreen: @escaping () -> Bool,
        openThread: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) {
        guard let model = model as? AgentV2Model, model.canRequestSupportFromHint else { return }
        presentSupportConfirmation(canConfirm: { [weak model] in model?.canRequestSupportFromHint == true }) { [weak model] in
            guard let model else { return }
            Task {
                let outcome = await model.requestSupportFromStarterHint(hasStayedOnScreen: hasStayedOnScreen)
                guard case .opened(let thread) = outcome else { return }
                openThread(thread)
            }
        }
    }

    /// Keeps the support sheet's Call enabled only while the chat can ask, as the chat changes under it
    func updateSupportConfirmation() {
        AgentSupportRequest.findCallAction(in: supportConfirmation)?.isEnabled = canConfirmSupportRequest()
    }

    private func presentSupportConfirmation(canConfirm: @escaping () -> Bool, onConfirm: @escaping () -> Void) {
        guard let viewController, viewController.presentedViewController == nil else { return }
        cancelDictation()
        let alert = AgentSupportRequest.makeConfirmation(
            hasWalletAddresses: (model as? AgentV2Model)?.hasSupportWalletAddresses == true,
            canConfirm: canConfirm,
            onConfirm: onConfirm
        )
        canConfirmSupportRequest = canConfirm
        supportConfirmation = alert
        presentConfirmation(alert, viewController)
    }

    /// Asks to delete the chat with the thread list's confirmation, then deletes its thread as the list does
    func confirmChatDeletion() {
        guard canDeleteChat, let viewController, viewController.presentedViewController == nil else { return }
        cancelDictation()
        let alert = UIAlertController(
            title: lang("Delete Chat?"),
            message: lang("$agent_delete_chat_confirmation"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: lang("Delete"), style: .destructive) { [weak self] _ in
            self?.deleteChat()
        })
        viewController.present(alert, animated: true)
    }

    func deleteChat() {
        guard canDeleteChat, let model = model as? AgentV2Model, model.beginChatDeletion() else { return }
        viewController?.view.endEditing(true)
        isDeletingChat = true
        refreshNavigationItemMenu()
        let closing = Task { [weak viewController] in
            guard let viewController else { return }
            await withCheckedContinuation { continuation in
                AgentEntryPoint.removeDeletedChat(viewController, animated: viewController.viewIfLoaded?.window != nil) {
                    continuation.resume()
                }
            }
        }
        Task { [showToast] in
            do {
                try await model.deleteChat()
            } catch {
                await closing.value
                if let displayError = AgentV2Copy.displayError(error) {
                    showToast(displayError.text)
                }
            }
        }
    }

    /// Opens the report form; after a failed send it opens again with the `failedComment` the user wrote
    func reportProblem(messageID: AgentItemID?, failedComment: String? = nil) {
        guard model.canReportProblem else { return }
        cancelDictation()
        let alert = AgentTextInputAlert.make(
            title: lang("Report a Problem"),
            message: lang(failedComment == nil ? "$agent_report_problem_description" : "$agent_report_problem_failed"),
            text: failedComment,
            placeholder: lang("Optional"),
            characterLimit: Self.problemReportCommentMaxLength,
            submitTitle: lang("Send")
        ) { [weak self] comment in
            self?.sendProblemReport(messageID: messageID, comment: comment)
        }
        viewController?.present(alert, animated: true)
    }

    @discardableResult
    func sendProblemReport(messageID: AgentItemID?, comment: String?) -> Task<Void, Never> {
        Task { [weak self, model, showError, showToast] in
            if await model.reportProblem(messageID: messageID, comment: comment) {
                showToast(lang("$agent_report_problem_sent"))
            } else if let self, self.model.canReportProblem,
                      let viewController = self.viewController,
                      viewController.viewIfLoaded?.window != nil, viewController.presentedViewController == nil {
                // A failed report opens again with its comment while the user is still on this screen and can report
                self.reportProblem(messageID: messageID, failedComment: comment ?? "")
            } else {
                self?.cancelDictation()
                showError(DisplayError(text: lang("$agent_report_problem_failed")))
            }
        }
    }

    /// Saves the answer's rating; `onCompletion` learns whether the rating is saved
    func rateMessage(
        _ messageID: AgentItemID,
        feedback: ApiAgentV2AnswerFeedback?,
        onCompletion: @escaping (Bool) -> Void
    ) {
        Task { [weak self, model, showError] in
            let didSave = await model.rateMessage(messageID: messageID, feedback: feedback)
            if !didSave {
                self?.cancelDictation()
                showError(DisplayError(text: lang("$agent_feedback_failed")))
            }
            onCompletion(didSave)
        }
    }
}
