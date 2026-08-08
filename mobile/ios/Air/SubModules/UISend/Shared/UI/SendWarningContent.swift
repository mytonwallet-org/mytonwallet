import Foundation
import WalletContext

enum SendWarningContent {
    static var domainScamMarkdown: String {
        lang(
            "$domain_like_scam_warning",
            arg1: "[\(lang("$help_center_prepositional"))](\(domainScamHelpUrl.absoluteString))"
        )
    }

    static var domainScamPlainText: String {
        lang(
            "$domain_like_scam_warning",
            arg1: lang("$help_center_prepositional")
        )
        .replacingOccurrences(of: "**", with: "")
    }

    static var seedPhraseScamMarkdown: String {
        lang(
            "$seed_phrase_scam_warning",
            arg1: "[\(lang("$help_center_prepositional"))](\(seedPhraseScamHelpUrl.absoluteString))"
        )
    }

    static var seedPhraseScamHelpUrl: URL {
        let value = Language.current == .ru
            ? HELP_CENTER_SEED_SCAM_URL_RU
            : HELP_CENTER_SEED_SCAM_URL
        return URL(string: value)!
    }

    static var domainScamHelpUrl: URL {
        let value = Language.current == .ru
            ? HELP_CENTER_DOMAIN_SCAM_URL_RU
            : HELP_CENTER_DOMAIN_SCAM_URL
        return URL(string: value)!
    }
}
