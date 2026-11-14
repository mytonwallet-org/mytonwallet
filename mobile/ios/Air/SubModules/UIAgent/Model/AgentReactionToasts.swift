import Foundation
import WalletContext
import WalletCore

/// The toasts that explain the reactions: the first like the user gives on this install says the agent will respond
/// more like this, and the first dislike that the answer will be reviewed. A support operator's reply has a like and a
/// dislike toast of its own, which say the support team gets the rating. Each shows once ever, whichever account or
/// chat it comes in, as Telegram's copy toast does, with the reaction's landing playing once where that toast plays its
/// copy icon.
@MainActor
final class AgentReactionToasts {
    static let shared = AgentReactionToasts(userDefaults: .standard)

    /// The square the landing plays in, its emoji 24 pt in the middle of it
    static let iconSize: CGFloat = 48

    private let userDefaults: UserDefaults
    private let showToast: (ToastConfig) -> Void

    init(userDefaults: UserDefaults, showToast: @escaping (ToastConfig) -> Void = { AppActions.showToast($0) }) {
        self.userDefaults = userDefaults
        self.showToast = showToast
    }

    /// The toast that explains `feedback` on an answer or, with `isOperatorReply`, on a support operator's reply
    static func makeToast(for feedback: ApiAgentV2AnswerFeedback, isOperatorReply: Bool = false) -> ToastConfig {
        ToastConfig(
            style: .overlay,
            icon: .animation(name: AgentReactionAnimations.getName(.center, of: feedback), size: iconSize),
            message: lang(getMessageKey(of: feedback, isOperatorReply: isOperatorReply)),
            transition: .scale
        )
    }

    /// Call as a reaction the user chose lands on its answer: shows its toast unless this install has shown it
    func explain(_ feedback: ApiAgentV2AnswerFeedback, isOperatorReply: Bool = false) {
        let key = Self.getShownKey(of: feedback, isOperatorReply: isOperatorReply)
        guard !userDefaults.bool(forKey: key) else { return }
        userDefaults.set(true, forKey: key)
        showToast(Self.makeToast(for: feedback, isOperatorReply: isOperatorReply))
    }

    private static func getShownKey(of feedback: ApiAgentV2AnswerFeedback, isOperatorReply: Bool) -> String {
        switch (feedback, isOperatorReply) {
        case (.like, false): "agent-feedback-liked-toast-shown"
        case (.dislike, false): "agent-feedback-disliked-toast-shown"
        case (.like, true): "agent-feedback-support-liked-toast-shown"
        case (.dislike, true): "agent-feedback-support-disliked-toast-shown"
        }
    }

    private static func getMessageKey(of feedback: ApiAgentV2AnswerFeedback, isOperatorReply: Bool) -> String {
        switch (feedback, isOperatorReply) {
        case (.like, false): "$agent_feedback_liked_toast"
        case (.dislike, false): "$agent_feedback_disliked_toast"
        case (.like, true): "$agent_feedback_support_liked_toast"
        case (.dislike, true): "$agent_feedback_support_disliked_toast"
        }
    }
}
