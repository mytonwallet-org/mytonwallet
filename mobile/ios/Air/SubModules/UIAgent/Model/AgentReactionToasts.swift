import Foundation
import WalletContext
import WalletCore

/// The toasts that explain the reactions: the first like the user gives on this install says the agent will respond
/// more like this, and the first dislike that the answer will be reviewed. Each shows once ever, whichever account or
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

    /// The toast that explains `feedback`
    static func makeToast(for feedback: ApiAgentV2AnswerFeedback) -> ToastConfig {
        ToastConfig(
            style: .overlay,
            icon: .animation(name: AgentReactionAnimations.getName(.center, of: feedback), size: iconSize),
            message: lang(getMessageKey(of: feedback)),
            transition: .scale
        )
    }

    /// Call as a reaction the user chose lands on its answer: shows its toast unless this install has shown it
    func explain(_ feedback: ApiAgentV2AnswerFeedback) {
        let key = Self.getShownKey(of: feedback)
        guard !userDefaults.bool(forKey: key) else { return }
        userDefaults.set(true, forKey: key)
        showToast(Self.makeToast(for: feedback))
    }

    private static func getShownKey(of feedback: ApiAgentV2AnswerFeedback) -> String {
        switch feedback {
        case .like: "agent-feedback-liked-toast-shown"
        case .dislike: "agent-feedback-disliked-toast-shown"
        }
    }

    private static func getMessageKey(of feedback: ApiAgentV2AnswerFeedback) -> String {
        switch feedback {
        case .like: "$agent_feedback_liked_toast"
        case .dislike: "$agent_feedback_disliked_toast"
        }
    }
}
