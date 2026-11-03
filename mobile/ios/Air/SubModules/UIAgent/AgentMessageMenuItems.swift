import ContextMenuKit
import UIKit
import WalletContext
import WalletCore

@MainActor
enum AgentMessageMenuItems {
    static func makeItems(
        for message: AgentMessage,
        copyText: String?,
        canRegenerate: Bool,
        canReportProblem: Bool,
        edit: @escaping () -> Void,
        regenerate: @escaping () -> Void,
        reportProblem: @escaping () -> Void
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        if let copyText {
            items.append(.action(ContextMenuAction(title: lang("Copy"), icon: .system("doc.on.doc")) {
                AgentClipboard.copy(copyText)
            }))
        }
        if message.role == .user {
            items.append(.action(ContextMenuAction(title: lang("Edit"), icon: .system("pencil"), handler: edit)))
        }
        if message.role == .assistant, canRegenerate {
            items.append(.action(ContextMenuAction(title: lang("Regenerate"), icon: .system("arrow.clockwise"), handler: regenerate)))
        }
        // An answer still being written has no stored message to report yet
        if message.role == .assistant, !message.isStreaming, canReportProblem {
            items.append(.action(ContextMenuAction(title: lang("Report a Problem"), icon: .system("flag"), handler: reportProblem)))
        }
        return items
    }

    static func makeItems(
        for news: ApiAgentV2ThreadNewsCard,
        openSource: @escaping () -> Void,
        share: @escaping (String) -> Void
    ) -> [ContextMenuItem] {
        makeItems(for: AgentNewsPostView.Content(news: news), openSource: openSource, share: share)
    }

    /// The menu of a news post, in the News feed and at the top of its discussion alike
    static func makeItems(
        for post: AgentNewsPostView.Content,
        openSource: @escaping () -> Void,
        share: @escaping (String) -> Void
    ) -> [ContextMenuItem] {
        let text = post.copyText
        return AgentNewsPostAction.getActions(for: post).map { action in
            .action(ContextMenuAction(title: action.title, icon: .system(action.systemImageName)) {
                switch action {
                case .openSource:
                    openSource()
                case .copy:
                    AgentClipboard.copy(text)
                case .share:
                    share(text)
                }
            })
        }
    }

    static func copyText(for message: AgentMessage) -> String? {
        var parts: [String] = []
        if !message.text.isEmpty {
            parts.append(message.text)
        }
        if let supplementaryErrorText = message.supplementaryErrorText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !supplementaryErrorText.isEmpty {
            parts.append(supplementaryErrorText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    static func copyText(for news: ApiAgentV2ThreadNewsCard) -> String {
        AgentNewsPostView.Content(news: news).copyText
    }
}

/// What a news post offers to do with it: its menu and the footer of its picture in the media viewer offer the same
enum AgentNewsPostAction: Equatable {
    case openSource
    case copy
    case share

    static func getActions(for post: AgentNewsPostView.Content) -> [AgentNewsPostAction] {
        (post.canOpenSource ? [.openSource] : []) + [.copy, .share]
    }

    var title: String {
        switch self {
        case .openSource: lang("$agent_news_open_source")
        case .copy: lang("Copy")
        case .share: lang("Share")
        }
    }

    var systemImageName: String {
        switch self {
        case .openSource: "arrow.up.right.square"
        case .copy: "doc.on.doc"
        case .share: "square.and.arrow.up"
        }
    }
}
