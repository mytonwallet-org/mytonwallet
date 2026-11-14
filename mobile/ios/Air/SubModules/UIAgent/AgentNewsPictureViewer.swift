import ContextMenuKit
import UIComponents
import UIKit
import WalletContext
import WalletCore

/// News pictures in the media viewer, as Telegram's gallery shows a chat's pictures: the post's date on the capsule over
/// the picture, under "N of M" among several, the post's sources in a menu at the header's trailing end, the post under
/// it as the caption, and Share and Copy as the footer's buttons. The feed and a discussion open their pictures through
/// it.
@MainActor
enum AgentNewsPictureViewer {
    struct Post {
        let content: AgentNewsPostView.Content
        /// When the post came, as its menu dates it
        let date: Date
        /// The picture as the list shows it
        let image: UIImage?
        /// The feed's language the post was shown in, which its share link carries
        let locale: String?
    }

    /// Telegram's caption: 17 pt white text, its links in Telegram's light blue
    static let captionFont = UIFont.systemFont(ofSize: 17)
    static let captionTitleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    static let linkColor = UIColor(red: 0x5a / 255, green: 0xc8 / 255, blue: 0xfa / 255, alpha: 1)

    /// Opens `posts`' pictures at the one of `index`; `openSource` opens a source's link
    @discardableResult
    static func present(
        posts: [Post],
        index: Int,
        in window: UIWindow,
        openSource: @escaping (String) -> Void,
        source: @escaping MediaViewer.SourceProvider
    ) -> MediaViewer? {
        weak var presentedViewer: MediaViewer?
        let pictures = posts.map { post in
            MediaViewer.Picture(
                url: post.content.imageURL,
                image: post.image,
                title: post.content.headline,
                details: makeDetails(for: post, getViewer: { presentedViewer }, openSource: openSource)
            )
        }
        let viewer = MediaViewer.present(pictures: pictures, index: index, in: window, source: source)
        presentedViewer = viewer
        return viewer
    }

    static func makeDetails(
        for post: Post,
        getViewer: @escaping () -> MediaViewer?,
        openSource: @escaping (String) -> Void
    ) -> MediaViewer.Details {
        let content = post.content
        let (date, time) = AgentModel.formatChatDate(for: post.date)
        // Telegram's footer keeps its forward button at the leading end
        let share = content.makeShareItems(locale: post.locale).map { activityItems in
            MediaViewer.Action(
                title: AgentNewsPostAction.share.title,
                image: UIImage(systemName: AgentNewsPostAction.share.systemImageName, withConfiguration: MediaViewer.Action.symbolConfiguration),
                placement: .leading
            ) { sourceView in
                let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                topViewController()?.presentActivityViewController(controller, sourceView: sourceView)
            }
        }
        let copy = MediaViewer.Action(
            title: AgentNewsPostAction.copy.title,
            image: UIImage(systemName: AgentNewsPostAction.copy.systemImageName, withConfiguration: MediaViewer.Action.symbolConfiguration),
            placement: .trailing
        ) { _ in
            AgentClipboard.copy(content.copyText) { toast in
                if let viewer = getViewer() {
                    viewer.toastController.showToast(toast)
                } else {
                    AppActions.showToast(toast)
                }
            }
        }
        return MediaViewer.Details(
            date: "\(date), \(time)",
            caption: makeCaption(for: content),
            actions: [share, copy].compactMap { $0 },
            menu: makeSourcesMenu(for: content, getViewer: getViewer, openSource: openSource),
            onLinkTap: { url in
                getViewer()?.closeFading()
                AgentMessageLinks.openMessageURL(url, renderingPolicy: .agentV2Safe)
            }
        )
    }

    /// The post's sources, as its menu's Sources lists them, each opening its link over the list as the viewer fades
    private static func makeSourcesMenu(
        for content: AgentNewsPostView.Content,
        getViewer: @escaping () -> MediaViewer?,
        openSource: @escaping (String) -> Void
    ) -> MediaViewer.Menu? {
        guard !content.sources.isEmpty else { return nil }
        return MediaViewer.Menu(
            title: lang("$agent_news_sources"),
            image: UIImage(systemName: AgentNewsPostAction.openSource.systemImageName, withConfiguration: WGlassButtonMetrics.symbolConfiguration)
        ) {
            var style = ContextMenuStyle.default
            style.minWidth = 180
            style.maxWidth = 250
            style.horizontalAlignment = .trailing
            return ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: content.sources.map { source in
                    .action(ContextMenuAction(title: source.name) {
                        getViewer()?.closeFading()
                        openSource(source.url)
                    })
                }),
                // The menu grows out of its button over the picture, which stays in view without a blur
                backdrop: .none,
                userInterfaceStyle: .dark,
                style: style
            )
        }
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
