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
    /// The user confirmed deletion, so the screen closes before server cleanup finishes.
    private(set) var isDeletingChat = false

    init(
        model: AgentModel,
        viewController: UIViewController,
        cancelDictation: @escaping () -> Void,
        refreshNavigationItemMenu: @escaping () -> Void,
        showError: @escaping (DisplayError) -> Void = { AppActions.showError(error: $0) },
        showToast: @escaping (String) -> Void = { AppActions.showToast(message: $0) }
    ) {
        self.model = model
        self.viewController = viewController
        self.cancelDictation = cancelDictation
        self.refreshNavigationItemMenu = refreshNavigationItemMenu
        self.showError = showError
        self.showToast = showToast
    }

    var canDeleteChat: Bool {
        !isDeletingChat && (model as? AgentV2Model)?.canDeleteChat == true
    }

    /// A chat whose thread is on its way: it has its question or its news post, or is opening
    var willHaveMenu: Bool {
        if isDeletingChat { return true }
        guard let model = model as? AgentV2Model else { return false }
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

    func rateMessage(_ messageID: AgentItemID, feedback: ApiAgentV2AnswerFeedback?) {
        Task { [weak self, model, showError] in
            let didFail = await !model.rateMessage(messageID: messageID, feedback: feedback)
            guard didFail else { return }
            self?.cancelDictation()
            showError(DisplayError(text: lang("$agent_feedback_failed")))
        }
    }
}
