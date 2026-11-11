import UIComponents
import UIKit
import WalletContext
import WalletCore

/// News pictures in the media viewer, as Telegram's gallery shows a chat's pictures: the post's date on the capsule over
/// the picture, under "N of M" among several, the post under it as the caption, and the post's menu as the footer's
/// buttons. The feed and a discussion open their pictures through it.
@MainActor
enum AgentNewsPictureViewer {
    struct Post {
        let content: AgentNewsPostView.Content
        /// When the post came, as its menu dates it
        let date: Date
        /// The picture as the list shows it
        let image: UIImage?
    }

    /// Telegram's caption: 17 pt white text, its links in Telegram's light blue
    static let captionFont = UIFont.systemFont(ofSize: 17)
    static let captionTitleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    static let linkColor = UIColor(red: 0x5a / 255, green: 0xc8 / 255, blue: 0xfa / 255, alpha: 1)

    /// Opens `posts`' pictures at the one of `index`; `openSource` opens the source of the post of an index
    @discardableResult
    static func present(
        posts: [Post],
        index: Int,
        in window: UIWindow,
        openSource: @escaping (Int) -> Void,
        source: @escaping MediaViewer.SourceProvider
    ) -> MediaViewer? {
        weak var presentedViewer: MediaViewer?
        let pictures = posts.enumerated().map { offset, post in
            MediaViewer.Picture(
                url: post.content.imageURL,
                image: post.image,
                title: post.content.headline,
                details: makeDetails(for: post, getViewer: { presentedViewer }, openSource: { openSource(offset) })
            )
        }
        let viewer = MediaViewer.present(pictures: pictures, index: index, in: window, source: source)
        presentedViewer = viewer
        return viewer
    }

    static func makeDetails(
        for post: Post,
        getViewer: @escaping () -> MediaViewer?,
        openSource: @escaping () -> Void
    ) -> MediaViewer.Details {
        let content = post.content
        let (date, time) = AgentModel.formatChatDate(for: post.date)
        let actions = AgentNewsPostAction.getActions(for: content).map { action in
            // Telegram's footer keeps its forward button at the leading end
            MediaViewer.Action(
                title: action.title,
                image: UIImage(systemName: action.systemImageName, withConfiguration: MediaViewer.Action.symbolConfiguration),
                placement: action == .share ? .leading : .trailing
            ) { sourceView in
                switch action {
                case .openSource:
                    // The source opens over the list, as a link in Telegram's gallery leaves it for the chat
                    getViewer()?.close()
                    openSource()
                case .copy:
                    AgentClipboard.copy(content.copyText) { toast in
                        if let viewer = getViewer() {
                            viewer.toastController.showToast(toast)
                        } else {
                            AppActions.showToast(toast)
                        }
                    }
                case .share:
                    let controller = UIActivityViewController(activityItems: [content.copyText], applicationActivities: nil)
                    topViewController()?.presentActivityViewController(controller, sourceView: sourceView)
                }
            }
        }
        return MediaViewer.Details(
            date: "\(date), \(time)",
            caption: makeCaption(for: content),
            actions: actions,
            onLinkTap: { url in
                getViewer()?.close()
                AgentMessageLinks.openMessageURL(url, renderingPolicy: .agentV2Safe)
            }
        )
    }

    /// The post's headline in bold over its body, with the body's own Markdown and links
    static func makeCaption(for content: AgentNewsPostView.Content) -> NSAttributedString {
        let caption = NSMutableAttributedString(
            string: content.headline,
            attributes: [.font: captionTitleFont, .foregroundColor: UIColor.white]
        )
        if let body = content.body {
            caption.append(NSAttributedString(string: "\n", attributes: [.font: captionFont, .foregroundColor: UIColor.white]))
            caption.append(AgentMessageTextRenderer.makeAttributedText(
                body,
                textColor: .white,
                rendersMarkdown: true,
                detectsLinks: false,
                markdownProfile: .agentMarkdownV1,
                baseFont: captionFont,
                linkColor: linkColor
            ))
        }
        return caption
    }
}
