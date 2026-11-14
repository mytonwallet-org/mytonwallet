import Foundation

/// Immutable normalized corpus used for repeated type-ahead queries.
public struct UniversalSearchIndex: Hashable, Sendable {
    public let documents: [SearchDocument]
    let entries: [IndexedSearchDocument]
    private let entryIndicesByGram: [String: [Int]]
    private let entryIndicesByExactIdentifier: [String: [Int]]

    /// Builds the index, reusing normalization from a previous index for every document whose
    /// searchable fields are unchanged. Signal-only updates — balances, prices, interaction
    /// counters — therefore rebuild without re-normalizing any text. When every document keeps its
    /// position and fields, the lookups keyed by position are reused as well.
    public init(documents: [SearchDocument] = [], reusing previous: UniversalSearchIndex? = nil) {
        self.documents = documents
        if let previous,
           previous.entries.count == documents.count,
           zip(previous.entries, documents).allSatisfy({ $0.document.id == $1.id && $0.document.fields == $1.fields }) {
            self.entries = zip(previous.entries, documents).map {
                IndexedSearchDocument(document: $1, reusingPreparationOf: $0)
            }
            self.entryIndicesByGram = previous.entryIndicesByGram
            self.entryIndicesByExactIdentifier = previous.entryIndicesByExactIdentifier
            return
        }
        if let previous {
            var previousByID = [SearchEntityID: IndexedSearchDocument](
                minimumCapacity: previous.entries.count
            )
            for entry in previous.entries {
                previousByID[entry.document.id] = entry
            }
            self.entries = documents.map { document in
                if let prior = previousByID[document.id], prior.document.fields == document.fields {
                    return IndexedSearchDocument(document: document, reusingPreparationOf: prior)
                }
                return IndexedSearchDocument(document)
            }
        } else {
            self.entries = documents.map(IndexedSearchDocument.init)
        }
        self.entryIndicesByGram = Self.makeGramIndex(entries: entries)
        self.entryIndicesByExactIdentifier = Self.makeExactIdentifierIndex(entries: entries)
    }

    func candidateEntries(for query: UniversalSearchQuery) -> [IndexedSearchDocument] {
        if query.requiresExactIdentifierMatch {
            return (entryIndicesByExactIdentifier[query.normalizedIdentifier] ?? [])
                .map { entries[$0] }
        }

        var indices = Set<Int>()
        for term in query.normalizedText.terms {
            for alternative in term.alternatives {
                guard let key = Self.leadingGramKey(alternative) else { continue }
                indices.formUnion(entryIndicesByGram[key] ?? [])
            }
        }
        return indices.sorted().map { entries[$0] }
    }

    private static func makeExactIdentifierIndex(
        entries: [IndexedSearchDocument]
    ) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for identifier in entry.exactIdentifierKeys {
                result[identifier, default: []].append(index)
            }
        }
        return result
    }

    private static func makeGramIndex(
        entries: [IndexedSearchDocument]
    ) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for key in entry.gramKeys {
                result[key, default: []].append(index)
            }
        }
        return result
    }

    static func gramKeys(_ value: String) -> Set<String> {
        let characters = Array(value)
        guard let first = characters.first else { return [] }
        guard characters.count > 1 else { return ["1:\(first)"] }

        var result = Set(characters.map { "1:\($0)" })
        for index in 0..<(characters.count - 1) {
            result.insert("2:\(characters[index])\(characters[index + 1])")
        }
        return result
    }

    private static func leadingGramKey(_ value: String) -> String? {
        let characters = Array(value)
        guard let first = characters.first else { return nil }
        guard characters.count > 1 else { return "1:\(first)" }
        return "2:\(first)\(characters[1])"
    }
}

struct IndexedSearchDocument: Hashable, Sendable {
    let document: SearchDocument
    let fields: [PreparedSearchField]
    let gramKeys: Set<String>
    let exactIdentifierKeys: Set<String>

    init(_ document: SearchDocument) {
        self.document = document
        let fields = document.fields
            .filter { !$0.value.isEmpty }
            .map(PreparedSearchField.init)
        self.fields = fields
        self.gramKeys = Self.makeGramKeys(fields: fields)
        self.exactIdentifierKeys = Self.makeExactIdentifierKeys(fields: fields)
    }

    /// The document carries updated signals while its searchable fields — and therefore all
    /// normalization and derived keys — are taken from the previously prepared entry
    init(document: SearchDocument, reusingPreparationOf previous: IndexedSearchDocument) {
        self.document = document
        self.fields = previous.fields
        self.gramKeys = previous.gramKeys
        self.exactIdentifierKeys = previous.exactIdentifierKeys
    }

    private static func makeGramKeys(fields: [PreparedSearchField]) -> Set<String> {
        var keys = Set<String>()
        for field in fields {
            for phrase in field.normalizedText.phraseAlternatives {
                keys.formUnion(UniversalSearchIndex.gramKeys(phrase))
            }
            keys.formUnion(UniversalSearchIndex.gramKeys(field.normalizedIdentifier))
        }
        return keys
    }

    private static func makeExactIdentifierKeys(fields: [PreparedSearchField]) -> Set<String> {
        var result = Set<String>()
        for field in fields {
            guard field.field.matchPolicy == .exact
                    || [.identifier, .address, .domain].contains(field.field.kind) else {
                continue
            }
            if !field.normalizedIdentifier.isEmpty {
                result.insert(field.normalizedIdentifier)
            }
        }
        return result
    }
}
