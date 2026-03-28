import Foundation

/// Searches DuckDuckGo for crypto news and summarizes results with the LLM —
actor NewsAnswerer {
    private let llm: LLMProvider
    private let i18n: I18n
    private let session: URLSession

    init(llm: LLMProvider, i18n: I18n) {
        self.llm = llm
        self.i18n = i18n
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Search for news and return an LLM-summarized answer.
    func answer(query: String, history: [ChatMessage] = [], lang: String) async throws -> String {
        let results = await searchDuckDuckGo(query: query)

        if results.isEmpty {
            return i18n.t("error.noNewsResults", lang: lang)
        }

        let context = buildContext(results)

        let langInstruction = lang == "en"
            ? "Answer in English."
            : "Answer in the same language as the user's message."

        let systemPrompt = i18n.t("prompt.news", lang: lang, args: [
            "context": context,
            "langInstruction": langInstruction,
        ])

        let messages = history + [ChatMessage(role: .user, content: query)]
        let answer = try await llm.generate(systemPrompt: systemPrompt, messages: messages)
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - DuckDuckGo HTML Lite

    private struct SearchResult {
        let title: String
        let body: String
        let href: String
    }

    private func searchDuckDuckGo(query: String, maxResults: Int = 5) async -> [SearchResult] {
        guard var components = URLComponents(string: "https://html.duckduckgo.com/html/") else {
            return []
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, _) = try? await session.data(for: request),
              let html = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return parseResults(html: html, max: maxResults)
    }

    /// Parse DuckDuckGo HTML lite results.
    private func parseResults(html: String, max: Int) -> [SearchResult] {
        var results: [SearchResult] = []

        // Extract result blocks: <a class="result__a" href="...">title</a>
        // and <a class="result__snippet">body</a>
        let linkPattern = try? NSRegularExpression(
            pattern: "<a[^>]+class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
            options: .dotMatchesLineSeparators
        )
        let snippetPattern = try? NSRegularExpression(
            pattern: "<a[^>]+class=\"result__snippet\"[^>]*>(.*?)</a>",
            options: .dotMatchesLineSeparators
        )

        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)

        let links = linkPattern?.matches(in: html, range: range) ?? []
        let snippets = snippetPattern?.matches(in: html, range: range) ?? []

        for i in 0..<min(links.count, max) {
            let link = links[i]
            let href = nsHTML.substring(with: link.range(at: 1))
            let rawTitle = nsHTML.substring(with: link.range(at: 2))
            let title = stripHTML(rawTitle)

            let body: String
            if i < snippets.count {
                body = stripHTML(nsHTML.substring(with: snippets[i].range(at: 1)))
            } else {
                body = ""
            }

            // Decode DuckDuckGo redirect URLs
            let finalHref: String
            if href.contains("uddg="), let comps = URLComponents(string: href),
               let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value {
                finalHref = uddg
            } else {
                finalHref = href
            }

            results.append(SearchResult(title: title, body: body, href: finalHref))
        }

        return results
    }

    private func buildContext(_ results: [SearchResult]) -> String {
        results.enumerated().map { i, r in
            "[\(i + 1)] \(r.title)\n\(r.body)\nSource: \(r.href)"
        }.joined(separator: "\n\n")
    }

    private func stripHTML(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>") else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
