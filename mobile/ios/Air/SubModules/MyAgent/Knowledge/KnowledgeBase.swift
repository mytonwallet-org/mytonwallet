import Foundation
import ZIPFoundation

/// Downloads, caches, and loads knowledge-base files, then retrieves relevant chunks
/// using TF-IDF scoring with bigrams, substring matching, source boosting,
/// and cross-file link following.
public actor KnowledgeBase {
    public static let shared = KnowledgeBase()
    private init() {}

    private var chunks: [Chunk] = []
    /// Quick-answer chunks from index.txt — always included as base context.
    private var quickAnswerChunks: [Chunk] = []
    private var loadedVersion: String?
    private var pendingVersion: String?
    private var retryTask: Task<Void, Never>?

    struct Chunk {
        let text: String
        let textLower: String
        /// Source filename without extension (e.g. "push", "staking").
        let source: String
        let termFrequency: [String: Int]
    }

    // MARK: - Loading

    /// Load (or reload) the knowledge base for the given version.
    /// Retries automatically on failure every 5 seconds until success or a new version is requested.
    public func load(version: String) {
        guard version != loadedVersion else { return }
        pendingVersion = version
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            await self?.loadWithRetry(version: version)
        }
    }

    private func loadWithRetry(version: String) async {
        while !Task.isCancelled && pendingVersion == version && loadedVersion != version {
            do {
                try await doLoad(version: version)
                guard pendingVersion == version else { return }
                loadedVersion = version
            } catch {
                guard !Task.isCancelled, pendingVersion == version else { return }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func doLoad(version: String) async throws {
        let dataURL = try await cachedDataURL(version: version)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dataURL, includingPropertiesForKeys: nil) else { return }

        var allChunks: [Chunk] = []
        var indexContent: String?

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "md" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let source = fileURL.deletingPathExtension().lastPathComponent

            if source == "index" {
                indexContent = content
                continue
            }

            let splits = splitMarkdown(content, chunkSize: 1000, overlap: 200)
            for text in splits {
                allChunks.append(makeChunk(text: text, source: source))
            }
        }

        chunks = allChunks

        // Parse index.txt: extract Quick Answers section as always-included context
        if let index = indexContent {
            quickAnswerChunks = parseQuickAnswers(from: index)
        }
    }

    // MARK: - Download & Cache

    private func cachedDataURL(version: String) async throws -> URL {
        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyAgent/knowledge-base")
            .appendingPathComponent(version)

        let baseDir = cacheDir.deletingLastPathComponent()

        // Already cached
        if fm.fileExists(atPath: cacheDir.path) {
            return cacheDir
        }

        let downloadURL = URL(
            string: "https://github.com/mytonwallet-org/knowledge-base/releases/download/\(version)/knowledge-base.zip"
        )!

        let (zipFileURL, response) = try await URLSession.shared.download(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw KnowledgeBaseError.downloadFailed(version: version)
        }

        // Extract to a temp directory first
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        try fm.unzipItem(at: zipFileURL, to: tempDir, pathEncoding: .utf8)
        try? fm.removeItem(at: zipFileURL)

        // Create cache directory
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Find the extracted root (may be nested in a folder)
        let extracted = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let sourceDir: URL
        if extracted.count == 1, let isDir = try? extracted[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
            sourceDir = extracted[0]
        } else {
            sourceDir = tempDir
        }

        // Copy files, renaming .md → .txt
        guard let enumerator = fm.enumerator(at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return cacheDir
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
            let destURL = cacheDir.appendingPathComponent(relativePath)
            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: fileURL, to: destURL)
        }

        removeOtherVersions(in: baseDir, keeping: version)
        return cacheDir
    }

    private nonisolated func removeOtherVersions(in baseDir: URL, keeping version: String) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else { return }
        for dir in contents where dir.lastPathComponent != version {
            try? fm.removeItem(at: dir)
        }
    }

    // MARK: - Retrieval

    /// Retrieve relevant context for a query.
    /// Returns: quick answers matching the query + top-k TF-IDF chunks + chunks from linked files.
    public func retrieve(_ query: String, k: Int = 8) -> [String] {
        if loadedVersion == nil { return [] }

        let queryLower = query.lowercased()
        let queryUnigrams = tokenize(queryLower)
        let queryBigrams = makeBigrams(queryUnigrams)
        let queryTerms = queryUnigrams + queryBigrams

        if queryTerms.isEmpty { return [] }

        let rawQueryWords = queryLower
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        // 1. Find matching quick answers from index.txt
        let matchingQA = scoreAndRank(
            chunks: quickAnswerChunks,
            queryTerms: queryTerms,
            rawQueryWords: rawQueryWords,
            queryLower: queryLower
        )
        let topQA = matchingQA.prefix(3).map(\.text)

        // 2. Score and rank all content chunks
        let rankedChunks = scoreAndRank(
            chunks: chunks,
            queryTerms: queryTerms,
            rawQueryWords: rawQueryWords,
            queryLower: queryLower
        )
        let topChunks = Array(rankedChunks.prefix(k))

        // 3. Follow file references: find linked sources mentioned in top chunks
        var includedSources = Set(topChunks.map(\.source))
        var linkedChunks: [Chunk] = []

        for chunk in topChunks {
            let referencedFiles = extractFileReferences(from: chunk.text)
            for refSource in referencedFiles where !includedSources.contains(refSource) {
                includedSources.insert(refSource)
                // Add the best chunk from the referenced file
                let fileChunks = chunks.filter { $0.source == refSource }
                let ranked = scoreAndRank(
                    chunks: fileChunks,
                    queryTerms: queryTerms,
                    rawQueryWords: rawQueryWords,
                    queryLower: queryLower
                )
                if let best = ranked.first {
                    linkedChunks.append(best)
                }
            }
        }

        // Assemble: quick answers first, then top chunks, then linked chunks
        var result: [String] = topQA
        result += topChunks.map(\.text)
        result += linkedChunks.prefix(3).map(\.text)

        return result.map(stripFileReferences)
    }

    // MARK: - Scoring

    private func scoreAndRank(
        chunks: [Chunk],
        queryTerms: [String],
        rawQueryWords: [String],
        queryLower: String
    ) -> [Chunk] {
        let n = Double(chunks.count)

        var idf: [String: Double] = [:]
        for term in queryTerms {
            let docFreq = chunks.filter { $0.termFrequency[term] != nil }.count
            idf[term] = docFreq > 0 ? log(n / Double(docFreq)) : 0
        }

        var scored: [(score: Double, chunk: Chunk)] = []
        for chunk in chunks {
            var score = 0.0

            // TF-IDF (unigrams + bigrams)
            for term in queryTerms {
                let tf = Double(chunk.termFrequency[term] ?? 0)
                score += tf * (idf[term] ?? 0)
            }

            // Exact substring bonus
            for word in rawQueryWords {
                if chunk.textLower.contains(word) {
                    score += 2.0
                }
            }

            // Full query phrase match
            if queryLower.count > 3, chunk.textLower.contains(queryLower) {
                score += 5.0
            }

            // Source filename bonus
            for word in rawQueryWords where word.count >= 3 {
                if chunk.source.contains(word) {
                    score += 3.0
                }
            }

            if score > 0 {
                scored.append((score, chunk))
            }
        }

        scored.sort { $0.score > $1.score }
        return scored.map(\.chunk)
    }

    // MARK: - Index Parsing

    /// Extract Quick Answers section from index.txt as individual Q&A chunks.
    private func parseQuickAnswers(from text: String) -> [Chunk] {
        // Find the "## Quick Answers" section
        guard let qaRange = text.range(of: "## Quick Answers") else { return [] }
        let qaSection = String(text[qaRange.lowerBound...])

        // Stop at next "---" or "## " section
        let endMarkers = ["---", "\n## "]
        var endIndex = qaSection.endIndex
        for marker in endMarkers {
            if let range = qaSection.range(of: marker, range: qaSection.index(after: qaSection.startIndex)..<qaSection.endIndex) {
                if range.lowerBound < endIndex {
                    endIndex = range.lowerBound
                }
            }
        }
        let qaContent = String(qaSection[qaSection.startIndex..<endIndex])

        // Split into individual Q&A pairs by "### " headers
        var qaChunks: [Chunk] = []
        let parts = qaContent.components(separatedBy: "\n### ")
        for part in parts.dropFirst() { // skip the "## Quick Answers" header
            let trimmed = "### " + part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                qaChunks.append(makeChunk(text: trimmed, source: "index"))
            }
        }

        return qaChunks
    }

    // MARK: - File References

    /// Extract referenced file names from text (e.g. `features/push.md` → "push").
    private func extractFileReferences(from text: String) -> [String] {
        // Match patterns like `features/push.md`, `security/backup.md`, See features/push.txt
        guard let regex = try? NSRegularExpression(
            pattern: "(?:`|\\b)(?:[a-z-]+/)?([a-z][a-z0-9-]+)\\.(?:md|txt)(?:`|\\b)",
            options: []
        ) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var sources: [String] = []
        for match in matches where match.numberOfRanges > 1 {
            let name = nsText.substring(with: match.range(at: 1))
            sources.append(name)
        }
        return sources
    }

    // MARK: - Text Cleaning

    /// Remove file references like `See features/push.md` from text before sending to LLM.
    private nonisolated func stripFileReferences(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\\s*See\\s+`?(?:[a-z-]+/)?[a-z][a-z0-9-]+\\.(?:md|txt)`?\\.?",
            options: .caseInsensitive
        ) else { return text }
        let nsText = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: nsText.length), withTemplate: "")
    }

    // MARK: - Private Helpers

    private func makeChunk(text: String, source: String) -> Chunk {
        let lower = text.lowercased()
        return Chunk(
            text: text,
            textLower: lower,
            source: source,
            termFrequency: buildTermFrequency(lower)
        )
    }

    private func splitMarkdown(_ text: String, chunkSize: Int, overlap: Int) -> [String] {
        let sections: [String]
        if let regex = try? NSRegularExpression(pattern: "\\n(?=#{1,3}\\s)") {
            let nsText = text as NSString
            var parts: [String] = []
            var lastEnd = 0
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let part = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                parts.append(part)
                lastEnd = match.range.location + match.range.length
            }
            parts.append(nsText.substring(from: lastEnd))
            sections = parts
        } else {
            sections = [text]
        }

        var result: [String] = []
        for section in sections {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.count <= chunkSize {
                result.append(trimmed)
            } else {
                var start = trimmed.startIndex
                while start < trimmed.endIndex {
                    let end = trimmed.index(start, offsetBy: chunkSize, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                    result.append(String(trimmed[start..<end]))
                    let advance = chunkSize - overlap
                    start = trimmed.index(start, offsetBy: advance, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                }
            }
        }
        return result
    }

    private func buildTermFrequency(_ lowerText: String) -> [String: Int] {
        let unigrams = tokenize(lowerText)
        let bigrams = makeBigrams(unigrams)
        var freq: [String: Int] = [:]
        for word in unigrams + bigrams {
            freq[word, default: 0] += 1
        }
        return freq
    }

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private func makeBigrams(_ tokens: [String]) -> [String] {
        guard tokens.count >= 2 else { return [] }
        return zip(tokens, tokens.dropFirst()).map { "\($0)_\($1)" }
    }
}

enum KnowledgeBaseError: LocalizedError {
    case downloadFailed(version: String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let version):
            return "Failed to download knowledge base version \(version)"
        }
    }
}
