import Foundation

/// Lightweight i18n helper
/// Loads JSON translation files from the bundled Translations directory.
public final class I18n: @unchecked Sendable {
    public static let defaultLang = "en"

    public static let supportedLanguages = [
        "en", "de", "es", "pl", "ru", "th", "tr", "uk", "zh-Hans", "zh-Hant",
    ]

    private let cache: NSCache<NSString, NSDictionary>

    public init() {
        self.cache = NSCache()
    }

    /// Get a translated string by dot-notation key, with optional interpolation.
    ///
    /// Falls back to English if the key is missing in the requested language.
    ///
    /// - Parameters:
    ///   - key: Dot-notation key (e.g. "send.button", "error.tokenNotFound").
    ///   - lang: ISO language code.
    ///   - args: Key-value pairs for `{placeholder}` substitution.
    /// - Returns: The translated, interpolated string. Returns the key itself if not found.
    public func t(_ key: String, lang: String = defaultLang, args: [String: String] = [:]) -> String {
        let strings = load(lang: lang)
        var template = strings[key] as? String
        if template == nil {
            // Fallback to English
            let enStrings = load(lang: Self.defaultLang)
            template = enStrings[key] as? String
        }
        guard var result = template else { return key }

        for (placeholder, value) in args {
            result = result.replacingOccurrences(of: "{\(placeholder)}", with: value)
        }
        return result
    }

    private func load(lang: String) -> NSDictionary {
        let cacheKey = lang as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let dict: NSDictionary
        if let url = Bundle.module.url(forResource: lang, withExtension: "json", subdirectory: "Translations"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            dict = json as NSDictionary
        } else {
            dict = NSDictionary()
        }

        cache.setObject(dict, forKey: cacheKey)
        return dict
    }
}
