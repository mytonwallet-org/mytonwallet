import Foundation
import WalletCore

enum AgentV2AnswerTables {
    private enum Fragment {
        case text(String)
        case table(ApiAgentV2DisplayTable)
    }

    private static let escapedScalars = CharacterSet(charactersIn: "&<>|\\`*_[]!")

    /// The answer text with its tables spliced in and its links marked for the renderer (`AgentTextLinks`)
    static func text(
        _ source: String,
        tables: [ApiAgentV2AnswerTable],
        references: [ApiAgentV2AnswerTableReference],
        links: [ApiAgentV2AnswerLink] = []
    ) -> String {
        guard !references.isEmpty else {
            return AgentTextLinks.mark(source, links: links, tableOffsets: []).text
        }
        return composeFragments(source, tables: tables, references: references, links: links).map { fragment in
            switch fragment {
            case .text(let text): text
            case .table(let table): "\n\n" + markdown(table) + "\n\n"
            }
        }.joined()
    }

    static func blocks(
        _ source: String,
        tables: [ApiAgentV2AnswerTable],
        references: [ApiAgentV2AnswerTableReference],
        links: [ApiAgentV2AnswerLink] = []
    ) -> [AgentMessageBlock] {
        composeFragments(source, tables: tables, references: references, links: links).flatMap { fragment -> [AgentMessageBlock] in
            switch fragment {
            case .text(let text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
                return AgentMessageBlockParser.parse(text)
            case .table(let content):
                let notes = content.notes.flatMap { AgentMessageBlockParser.parse($0) }
                guard !content.rows.isEmpty else { return notes }
                let headers = content.headers.map {
                    AgentMessageTableCell(text: $0, isHeader: true, isPlainText: true)
                }
                let rows = content.rows.map { row in
                    row.map { AgentMessageTableCell(text: $0, isPlainText: true) }
                }
                return notes + [.table(AgentMessageTable(rows: [headers] + rows))]
            }
        }
    }

    private static func composeFragments(
        _ text: String,
        tables: [ApiAgentV2AnswerTable],
        references: [ApiAgentV2AnswerTableReference],
        links: [ApiAgentV2AnswerLink]
    ) -> [Fragment] {
        let marked = AgentTextLinks.mark(text, links: links, tableOffsets: references.map(\.textOffset))
        let source = marked.text as NSString
        var offset = 0
        var fragments: [Fragment] = []
        for (reference, textOffset) in zip(references, marked.tableOffsets) {
            // A streaming snapshot may arrive before the text preceding its table
            guard textOffset >= offset, textOffset <= source.length,
                  let table = tables.first(where: { $0.id == reference.tableId }) else { continue }
            fragments.append(.text(source.substring(with: NSRange(location: offset, length: textOffset - offset))))
            fragments.append(.table(table.content))
            offset = textOffset
        }
        fragments.append(.text(source.substring(from: offset)))
        return fragments
    }

    private static func markdown(_ content: ApiAgentV2DisplayTable) -> String {
        let table = content.rows.isEmpty ? "" :
            ([line(content.headers), line(content.headers.map { _ in "---" })] + content.rows.map(line))
                .joined(separator: "\n")
        return (content.notes + [table]).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func line(_ cells: [String]) -> String {
        "| " + cells.map { cell in
            cell.unicodeScalars.map { scalar in
                if escapedScalars.contains(scalar) { return "&#\(scalar.value);" }
                return CharacterSet.newlines.contains(scalar) ? " " : String(scalar)
            }.joined()
        }.joined(separator: " | ") + " |"
    }
}
