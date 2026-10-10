import UIKit
import WalletContext
import WalletCore

/// Answer links travel inside message text as private-use markers around their labels, so they survive table
/// splicing and block parsing; the renderer turns marked labels into links and removes the markers. A marker
/// carries its URL percent-encoded to letters, digits and `%`, which Markdown parsing leaves alone.
enum AgentTextLinks {
    private static let linkStart = "\u{E004}"
    private static let urlEnd = "\u{E005}"
    private static let linkEnd = "\u{E006}"
    private static let markedLink = try? NSRegularExpression(
        pattern: "\u{E004}([A-Za-z0-9%]*)\u{E005}([^\u{E004}\u{E005}\u{E006}]*)\u{E006}"
    )
    private static let strayMarker = try? NSRegularExpression(pattern: "[\u{E004}\u{E005}\u{E006}]")
    /// The deeplink commands that only open a screen, such as `settings/appearance`
    private static let appScreenPath = "^(explore|market|portfolio|multisend|settings(/[a-z][a-z0-9-]*)?)$"
    /// ASCII letters and digits; every other scalar of a URL is percent-encoded inside its marker
    private static let urlMarkerCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    )

    /// Marks the labels of `links` in `text`. A link the text does not cover yet, one that overlaps an earlier link or
    /// contains a table, and one the app may not open stay unmarked; `tableOffsets` move with the text.
    static func mark(
        _ text: String,
        links: [ApiAgentV2AnswerLink],
        tableOffsets: [Int]
    ) -> (text: String, tableOffsets: [Int]) {
        guard !links.isEmpty else { return (text, tableOffsets) }
        let source = text as NSString
        var marked = ""
        var offset = 0
        var insertions: [(location: Int, length: Int)] = []
        for link in links {
            let end = link.textOffset + link.textLength
            guard link.textOffset >= offset, link.textLength > 0, end <= source.length,
                  !tableOffsets.contains(where: { $0 > link.textOffset && $0 < end }),
                  let url = URL(string: link.url), isOpenable(url),
                  let encodedURL = link.url.addingPercentEncoding(withAllowedCharacters: urlMarkerCharacters) else { continue }
            let opening = linkStart + encodedURL + urlEnd
            marked += source.substring(with: NSRange(location: offset, length: link.textOffset - offset))
            marked += opening + source.substring(with: NSRange(location: link.textOffset, length: link.textLength)) + linkEnd
            insertions.append((link.textOffset, (opening as NSString).length + (linkEnd as NSString).length))
            offset = end
        }
        marked += source.substring(from: offset)
        // A table at the start of a link stays before it
        let movedOffsets = tableOffsets.map { tableOffset in
            insertions.reduce(tableOffset) { $1.location < tableOffset ? $0 + $1.length : $0 }
        }
        return (marked, movedOffsets)
    }

    static func containsLinks(_ text: String) -> Bool {
        text.contains(linkStart)
    }

    /// Marked text with each label followed by its URL, for copying
    static func copyText(_ text: String) -> String {
        guard containsLinks(text), let markedLink else { return text }
        let result = NSMutableString(string: text)
        for match in markedLink.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let label = result.substring(with: match.range(at: 2))
            let url = decodedURL(result.substring(with: match.range(at: 1)))
            result.replaceCharacters(in: match.range, with: url.map { copyText(label: label, url: $0) } ?? label)
        }
        return removingStrayMarkers(from: result as String)
    }

    /// Rendered text with each link's URL after its label, for copying
    static func copyText(from text: NSAttributedString) -> String {
        var result = ""
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let label = (text.string as NSString).substring(with: range)
            result += (value as? URL).map { copyText(label: label, url: $0) } ?? label
        }
        return result
    }

    /// Turns marked labels into links shown in `linkColor` and removes every marker
    static func resolve(in text: NSMutableAttributedString, linkColor: UIColor) {
        guard containsLinks(text.string) || text.string.contains(urlEnd) || text.string.contains(linkEnd) else { return }
        for match in markedLink?.matches(in: text.string, range: NSRange(location: 0, length: text.length)).reversed() ?? [] {
            let encodedURL = (text.string as NSString).substring(with: match.range(at: 1))
            let label = text.attributedSubstring(from: match.range(at: 2))
            text.replaceCharacters(in: match.range, with: label)
            guard label.length > 0, let url = decodedURL(encodedURL) else { continue }
            text.addAttributes(
                [.link: url, .foregroundColor: linkColor],
                range: NSRange(location: match.range.location, length: label.length)
            )
        }
        for match in strayMarker?.matches(in: text.string, range: NSRange(location: 0, length: text.length)).reversed() ?? [] {
            text.deleteCharacters(in: match.range)
        }
    }

    /// Whether the app opens `url` from answer text: `https` with a host and no credentials
    /// Whether the app may open `url` from an answer: an `https` page with a host and no credentials, or a link to a
    /// screen of the app, which its deeplink handler opens
    static func isOpenable(_ url: URL) -> Bool {
        isAppScreenLink(url)
            || url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }

    /// A deeplink of this app that only opens one of its screens, a settings section included
    static func isAppScreenLink(_ url: URL) -> Bool {
        let link = url.absoluteString
        return link.hasPrefix(SELF_PROTOCOL)
            && link.dropFirst(SELF_PROTOCOL.count).range(of: appScreenPath, options: .regularExpression) != nil
    }

    private static func decodedURL(_ encodedURL: String) -> URL? {
        guard let url = encodedURL.removingPercentEncoding.flatMap(URL.init(string:)), isOpenable(url) else { return nil }
        return url
    }

    private static func copyText(label: String, url: URL) -> String {
        label == url.absoluteString ? label : "\(label) (\(url.absoluteString))"
    }

    private static func removingStrayMarkers(from text: String) -> String {
        guard let strayMarker else { return text }
        return strayMarker.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: ""
        )
    }
}
