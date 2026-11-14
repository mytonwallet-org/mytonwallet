import ContextMenuKit
import UIKit
import WalletContext
import WalletCore

@MainActor
enum AgentMessageMenuItems {
    static func makeItems(
        for message: AgentMessage,
        copyText: String?,
        canEdit: Bool,
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
        if message.role == .user, canEdit {
            items.append(.action(ContextMenuAction(title: lang("Edit"), icon: .system("pencil"), handler: edit)))
        }
        if message.role == .assistant, canRegenerate {
            items.append(.action(ContextMenuAction(title: lang("Regenerate"), icon: .system("arrow.clockwise"), handler: regenerate)))
        }
        // An answer still being written has no stored message to report yet
        if message.author == .agent, message.supportEvent == nil,
           message.role == .assistant, !message.isStreaming, canReportProblem {
            items.append(.action(ContextMenuAction(title: lang("Report a Problem"), icon: .system("flag"), handler: reportProblem)))
        }
        return items
    }

    /// The menu of a news post, in the News feed and at the top of its discussion alike: Sources opens the list of its
    /// sources, each opening its link. Share gives `share` the post's share items in `locale`; a digest has no Share.
    static func makeItems(
        for post: AgentNewsPostView.Content,
        locale: String?,
        openSource: @escaping (String) -> Void,
        share: @escaping ([Any]) -> Void
    ) -> [ContextMenuItem] {
        let text = post.copyText
        var items: [ContextMenuItem] = []
        if !post.sources.isEmpty {
            items.append(.submenu(ContextMenuSubmenu(
                title: lang("$agent_news_sources"),
                icon: .system(AgentNewsPostAction.openSource.systemImageName),
                makePage: {
                    let back: [ContextMenuItem] = [
                        .back(ContextMenuBackAction(title: lang("Back"), icon: .airBundle("MenuBack"))),
                        .separator,
                    ]
                    return ContextMenuPage(items: back + post.sources.map { source in
                        .action(ContextMenuAction(title: source.name) { openSource(source.url) })
                    })
                }
            )))
        }
        items.append(makeItem(.copy) { AgentClipboard.copy(text) })
        if let shareItems = post.makeShareItems(locale: locale) {
            items.append(makeItem(.share) { share(shareItems) })
        }
        return items
    }

    static func makeItem(_ action: AgentNewsPostAction, handler: @escaping () -> Void) -> ContextMenuItem {
        .action(ContextMenuAction(title: action.title, icon: .system(action.systemImageName), handler: handler))
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
}

/// What a news post offers to do with it, as the footer of its picture in the media viewer offers it; its menu lists
/// the sources in place of opening the first
enum AgentNewsPostAction: Equatable {
    case openSource
    case copy
    case share

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
