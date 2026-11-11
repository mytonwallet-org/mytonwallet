import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The line under a news post's text that names its first sources, in the order the API gives them: "Sources: CoinDesk,
/// The Block". The feed's card and the discussion's post build it alike, as the card flies onto the post.
struct AgentNewsSourceLine: Equatable {
    struct Entry: Equatable {
        let name: String
        /// The source's link when a news source may open it; nil leaves the entry plain text
        let url: String?
    }

    struct Link: Equatable {
        let range: NSRange
        let url: String
    }

    private static let maxEntryCount = 3
    private static let placeholder = "\u{FFFC}"

    let entries: [Entry]
    let text: String
    /// The entries that open their sources, within `text`
    let links: [Link]

    /// Nil for news without a source to name. `legacySource`, the name a thread's news card stored before it had its
    /// sources, stands in for sources that name none.
    init?(sources: [ApiAgentV2NewsFeedItem.Source], legacySource: String? = nil) {
        var entries: [Entry] = []
        var shownNames = Set<String>()
        for source in sources where entries.count < Self.maxEntryCount {
            guard let name = Self.getName(of: source), shownNames.insert(name.lowercased()).inserted else { continue }
            entries.append(Entry(name: name, url: AgentTextLinks.newsSourceURL(source.url) == nil ? nil : source.url))
        }
        if entries.isEmpty, let legacyName = legacySource?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            entries = [Entry(name: legacyName, url: nil)]
        }
        guard !entries.isEmpty else { return nil }
        self.entries = entries

        let template = entries.count == 1
            ? langFormat("$agent_news_source", Self.placeholder)
            : langFormat("$agent_news_sources", Self.placeholder)
        let placeholderRange = (template as NSString).range(of: Self.placeholder)
        let separator = lang("$joining_comma")
        let names = entries.map(\.name).joined(separator: separator)
        guard placeholderRange.location != NSNotFound else {
            text = names
            links = []
            return
        }
        text = (template as NSString).replacingCharacters(in: placeholderRange, with: names)
        var location = placeholderRange.location
        var links: [Link] = []
        for entry in entries {
            let length = (entry.name as NSString).length
            if let url = entry.url {
                links.append(Link(range: NSRange(location: location, length: length), url: url))
            }
            location += length + (separator as NSString).length
        }
        self.links = links
    }

    /// The source's name, or its site without "www."
    private static func getName(of source: ApiAgentV2NewsFeedItem.Source) -> String? {
        if let name = source.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty { return name }
        guard let host = URL(string: source.url)?.host else { return nil }
        return (host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host).nilIfEmpty
    }
}

/// Shows an `AgentNewsSourceLine` in the gray of the post's time, wrapping rather than cutting it short. A tap on an
/// entry with a link opens that entry's source; the rest of the line is plain text.
final class AgentNewsSourceLineLabel: UILabel {
    var onLinkTap: ((String) -> Void)?
    private var links: [AgentNewsSourceLine.Link] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyTextStyle(.caption, scaling: .dynamic)
        textColor = .air.secondaryLabel
        textAlignment = .natural
        numberOfLines = 0
        lineBreakMode = .byWordWrapping
        isAccessibilityElement = false
        isHidden = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with line: AgentNewsSourceLine?) {
        text = line?.text
        links = line?.links ?? []
        isHidden = line == nil
        isUserInteractionEnabled = !links.isEmpty
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        openLink(at: recognizer.location(in: self))
    }

    /// Opens the source of the entry at `point`, if it has one
    func openLink(at point: CGPoint) {
        guard let url = getLinkURL(at: point) else { return }
        onLinkTap?(url)
    }

    private func getLinkURL(at point: CGPoint) -> String? {
        guard !links.isEmpty, let text, let font, bounds.contains(point) else { return nil }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        paragraphStyle.lineBreakMode = lineBreakMode
        let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: paragraphStyle])
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        // The label centers its text when it is laid out taller than the text
        let textHeight = layoutManager.usedRect(for: container).height
        let textPoint = CGPoint(x: point.x, y: point.y - max(0, (bounds.height - textHeight) / 2))
        let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: container)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.contains(textPoint) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return links.first { NSLocationInRange(characterIndex, $0.range) }?.url
    }
}
