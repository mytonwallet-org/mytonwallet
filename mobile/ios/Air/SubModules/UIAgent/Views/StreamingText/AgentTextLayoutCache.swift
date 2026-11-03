import UIKit

/// Answers laid out and drawn whole, for the next cell that shows the same answer the same way. A chat reuses its
/// cells as it scrolls, so without them every answer coming back into view would be parsed, laid out and drawn
/// again on the main thread. An entry costs the bytes of its drawing; the system empties the cache under memory
/// pressure. News posts, whose text a label lays out, keep their parsed text here the same way.
@MainActor
final class AgentTextLayoutCache {
    struct Key: Hashable {
        let text: String
        let textColor: UIColor
        let linkColor: UIColor
        let font: UIFont
        let rendersMarkdown: Bool
        let markdownProfile: AgentMessageMarkdownProfile
        let detectsLinks: Bool
        let maxWidth: CGFloat
    }

    static let shared = AgentTextLayoutCache()

    /// A few screens of long answers
    private static let totalCostLimit = 48 * 1024 * 1024

    private final class KeyBox: NSObject {
        let key: Key

        init(_ key: Key) {
            self.key = key
        }

        override var hash: Int { key.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? KeyBox)?.key == key
        }
    }

    private final class Entry {
        let layout: AgentStreamingTextLayout

        init(_ layout: AgentStreamingTextLayout) {
            self.layout = layout
        }
    }

    private let cache = NSCache<KeyBox, Entry>()
    private let texts = NSCache<KeyBox, NSAttributedString>()
    /// The texts of a few screens of news
    private static let textCountLimit = 200

    init() {
        cache.totalCostLimit = Self.totalCostLimit
        texts.countLimit = Self.textCountLimit
    }

    /// The text kept for `key`, whose width doesn't matter, or the one `make` renders, kept for the next time
    func getAttributedText(for key: Key, make: () -> NSAttributedString) -> NSAttributedString {
        let box = KeyBox(key)
        if let text = texts.object(forKey: box) {
            return text
        }
        let text = make()
        texts.setObject(text, forKey: box)
        return text
    }

    /// The layout kept for `key`, or the one `make` returns, kept for the next time
    func getLayout(for key: Key, make: () -> AgentStreamingTextLayout) -> AgentStreamingTextLayout {
        let box = KeyBox(key)
        if let entry = cache.object(forKey: box) {
            return entry.layout
        }
        let layout = make()
        let cost = layout.renderedImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(Entry(layout), forKey: box, cost: cost)
        return layout
    }
}
