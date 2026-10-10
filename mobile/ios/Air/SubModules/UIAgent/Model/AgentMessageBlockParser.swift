import Foundation

enum AgentMessageTableAlignment: Equatable {
    case start
    case center
    case end
}

enum AgentMessageTableVerticalAlignment: Equatable {
    case top
    case middle
    case bottom
}

struct AgentMessageTableCell: Equatable {
    let text: String
    let isHeader: Bool
    let isPlainText: Bool
    let alignment: AgentMessageTableAlignment
    let verticalAlignment: AgentMessageTableVerticalAlignment
    let columnSpan: Int
    let rowSpan: Int

    init(
        text: String,
        isHeader: Bool = false,
        isPlainText: Bool = false,
        alignment: AgentMessageTableAlignment = .start,
        verticalAlignment: AgentMessageTableVerticalAlignment = .top,
        columnSpan: Int = 1,
        rowSpan: Int = 1
    ) {
        self.text = text
        self.isHeader = isHeader
        self.isPlainText = isPlainText
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }
}

struct AgentMessageTable: Equatable {
    let rows: [[AgentMessageTableCell]]
    let title: String?
    let isBordered: Bool
    let isStriped: Bool

    init(
        rows: [[AgentMessageTableCell]],
        title: String? = nil,
        isBordered: Bool = true,
        isStriped: Bool = false
    ) {
        self.rows = rows
        self.title = title
        self.isBordered = isBordered
        self.isStriped = isStriped
    }
}

enum AgentMessageBlock: Equatable {
    case text(String)
    case table(AgentMessageTable)
}

struct AgentPlacedTableCell: Equatable {
    let cell: AgentMessageTableCell
    let row: Int
    let column: Int
}

struct AgentMessageTableGrid: Equatable {
    let cells: [AgentPlacedTableCell]
    let rowCount: Int
    let columnCount: Int
}

enum AgentMessageBlockParser {
    private static let htmlTableOpenExpression = expression(#"<\s*table(?:\s|>|$)"#, options: .caseInsensitive)
    private static let htmlTableCloseExpression = expression(#"</\s*table\s*>"#, options: .caseInsensitive)
    private static let htmlTableTokenExpression = expression(
        #"<\s*(/?)\s*(table|caption|thead|tbody|tfoot|tr|td|th|br)\b([^>]*)>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let htmlAttributeExpression = expression(
        #"([a-z_:][a-z0-9_.:-]*)(?:\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+)))?"#,
        options: .caseInsensitive
    )
    private static let htmlBreakExpression = expression(#"<\s*br\s*/?\s*>"#, options: .caseInsensitive)
    private static let htmlLinkExpression = expression(
        #"<\s*a\b([^>]*)>(.*?)</\s*a\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let htmlBoldExpression = expression(
        #"<\s*(?:b|strong)\b[^>]*>(.*?)</\s*(?:b|strong)\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let htmlItalicExpression = expression(
        #"<\s*(?:i|em)\b[^>]*>(.*?)</\s*(?:i|em)\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let htmlCodeExpression = expression(
        #"<\s*code\b[^>]*>(.*?)</\s*code\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let htmlTagExpression = expression(#"<[^>]+>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let numericHTMLEntityExpression = expression(#"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#)
    private static let tableDelimiterExpression = expression(#"^:?-+:?$"#)

    private struct CodeFenceMarker {
        let character: Character
        let length: Int
        let remainder: String
    }

    private struct ActiveCodeFence {
        let character: Character
        let length: Int
        let startLocation: Int
    }

    static func parse(_ source: String) -> [AgentMessageBlock] {
        let normalizedSource = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let string = normalizedSource as NSString
        let fencedCodeBlockRanges = fencedCodeBlockRanges(in: normalizedSource)
        var blocks: [AgentMessageBlock] = []
        var textStart = 0
        var searchIndex = 0

        while searchIndex < string.length {
            let remainingRange = NSRange(location: searchIndex, length: string.length - searchIndex)
            let tableMatch = htmlTableOpenExpression.firstMatch(in: normalizedSource, range: remainingRange)
            guard let tableMatch else { break }
            if fencedCodeBlockRanges.contains(where: {
                NSLocationInRange(tableMatch.range.location, $0)
            }) {
                searchIndex = NSMaxRange(tableMatch.range)
                continue
            }

            let openingSearchRange = NSRange(
                location: tableMatch.range.location,
                length: string.length - tableMatch.range.location
            )
            let openingEnd = string.range(of: ">", options: [], range: openingSearchRange)
            guard openingEnd.location != NSNotFound else { break }
            let closingSearchStart = NSMaxRange(openingEnd)
            let closingMatch = htmlTableCloseExpression.firstMatch(
                in: normalizedSource,
                range: NSRange(location: closingSearchStart, length: string.length - closingSearchStart)
            )
            guard let closingMatch else { break }

            let tableRange = NSRange(
                location: tableMatch.range.location,
                length: NSMaxRange(closingMatch.range) - tableMatch.range.location
            )
            let tableSource = string.substring(with: tableRange)
            guard let table = parseHTMLTable(tableSource) else {
                searchIndex = NSMaxRange(tableRange)
                continue
            }

            addMarkdownBlocks(
                string.substring(with: NSRange(location: textStart, length: tableRange.location - textStart)),
                to: &blocks
            )
            blocks.append(.table(table))
            textStart = NSMaxRange(tableRange)
            searchIndex = textStart
        }

        addMarkdownBlocks(
            string.substring(with: NSRange(location: textStart, length: string.length - textStart)),
            to: &blocks
        )
        return blocks.isEmpty ? [.text(normalizedSource)] : blocks
    }

    static func resolveGrid(_ table: AgentMessageTable) -> AgentMessageTableGrid {
        var cells: [AgentPlacedTableCell] = []
        var occupiedUntilRow: [Int: Int] = [:]
        var columnCount = 0
        var rowCount = table.rows.count

        for (rowIndex, row) in table.rows.enumerated() {
            var column = 0
            for cell in row {
                let columnSpan = max(cell.columnSpan, 1)
                let rowSpan = max(cell.rowSpan, 1)
                while (column..<(column + columnSpan)).contains(where: {
                    occupiedUntilRow[$0, default: 0] > rowIndex
                }) {
                    column += 1
                }

                cells.append(AgentPlacedTableCell(cell: cell, row: rowIndex, column: column))
                for occupiedColumn in column..<(column + columnSpan) {
                    occupiedUntilRow[occupiedColumn] = rowIndex + rowSpan
                }
                column += columnSpan
                columnCount = max(columnCount, column)
                rowCount = max(rowCount, rowIndex + rowSpan)
            }
        }

        return AgentMessageTableGrid(cells: cells, rowCount: rowCount, columnCount: columnCount)
    }

    private static func addMarkdownBlocks(_ source: String, to blocks: inout [AgentMessageBlock]) {
        guard !source.isEmpty else { return }
        let lines = source.components(separatedBy: "\n")
        var textLines: [String] = []
        var activeCodeFence: ActiveCodeFence?
        var lineIndex = 0

        func flushText() {
            let value = textLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !value.isEmpty {
                blocks.append(.text(value))
            }
            textLines.removeAll(keepingCapacity: true)
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if updateCodeFenceState(for: line, activeFence: &activeCodeFence) {
                textLines.append(line)
                lineIndex += 1
                continue
            }

            let parsedTable = activeCodeFence == nil && lineIndex + 1 < lines.count
                ? parseMarkdownTable(lines: lines, headerIndex: lineIndex)
                : nil
            guard let parsedTable else {
                textLines.append(line)
                lineIndex += 1
                continue
            }

            flushText()
            blocks.append(.table(parsedTable.table))
            lineIndex = parsedTable.nextLineIndex
        }
        flushText()
    }

    private struct ParsedMarkdownTable {
        let table: AgentMessageTable
        let nextLineIndex: Int
    }

    private static func parseMarkdownTable(lines: [String], headerIndex: Int) -> ParsedMarkdownTable? {
        let headerLine = lines[headerIndex]
        guard hasUnescapedPipe(headerLine) else { return nil }
        let header = splitTableRow(headerLine)
        guard header.count >= 2 else { return nil }

        let delimiter = splitTableRow(lines[headerIndex + 1])
        guard delimiter.count == header.count else { return nil }
        let alignments = delimiter.map(parseAlignment)
        guard alignments.allSatisfy({ $0 != nil }) else { return nil }
        let resolvedAlignments = alignments.compactMap { $0 }

        var rows = [
            header.enumerated().map { index, value in
                AgentMessageTableCell(
                    text: value,
                    isHeader: true,
                    alignment: resolvedAlignments[index]
                )
            },
        ]
        var lineIndex = headerIndex + 2
        while lineIndex < lines.count {
            let rowLine = lines[lineIndex]
            guard !rowLine.trimmingCharacters(in: .whitespaces).isEmpty,
                  hasUnescapedPipe(rowLine) else { break }
            let cells = splitTableRow(rowLine)
            rows.append((0..<header.count).map { column in
                AgentMessageTableCell(
                    text: cells.indices.contains(column) ? cells[column] : "",
                    alignment: resolvedAlignments[column]
                )
            })
            lineIndex += 1
        }
        return ParsedMarkdownTable(
            table: AgentMessageTable(rows: rows),
            nextLineIndex: lineIndex
        )
    }

    private static func parseAlignment(_ source: String) -> AgentMessageTableAlignment? {
        let marker = source.trimmingCharacters(in: .whitespaces)
        let range = NSRange(location: 0, length: (marker as NSString).length)
        guard tableDelimiterExpression.firstMatch(in: marker, range: range)?.range == range else { return nil }
        if marker.hasPrefix(":"), marker.hasSuffix(":") { return .center }
        if marker.hasSuffix(":") { return .end }
        return .start
    }

    private static func hasUnescapedPipe(_ line: String) -> Bool {
        var isEscaped = false
        for character in line {
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                return true
            }
        }
        return false
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }

        var cells: [String] = []
        var cell = ""
        var isEscaped = false
        for character in content {
            if isEscaped {
                if character != "|" { cell.append("\\") }
                cell.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(character)
            }
        }
        if isEscaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private struct HTMLCellDraft {
        let isHeader: Bool
        let alignment: AgentMessageTableAlignment
        let verticalAlignment: AgentMessageTableVerticalAlignment
        let columnSpan: Int
        let rowSpan: Int
        var content = ""
    }

    private static func parseHTMLTable(_ source: String) -> AgentMessageTable? {
        let string = source as NSString
        let matches = htmlTableTokenExpression.matches(
            in: source,
            range: NSRange(location: 0, length: string.length)
        )
        guard let firstMatch = matches.first else { return nil }

        let tableAttributes = parseHTMLAttributes(group(3, in: firstMatch, source: string))
        var rows: [[AgentMessageTableCell]] = []
        var currentRow: [AgentMessageTableCell]?
        var currentCell: HTMLCellDraft?
        var caption: String?
        var title: String?
        var previousEnd = 0

        func appendContent(_ value: String) {
            if currentCell != nil {
                currentCell!.content.append(value)
            } else if caption != nil {
                caption!.append(value)
            }
        }

        func finishCell() {
            guard let cell = currentCell else { return }
            currentRow?.append(AgentMessageTableCell(
                text: sanitizeInlineHTML(cell.content),
                isHeader: cell.isHeader,
                alignment: cell.alignment,
                verticalAlignment: cell.verticalAlignment,
                columnSpan: cell.columnSpan,
                rowSpan: cell.rowSpan
            ))
            currentCell = nil
        }

        func finishRow() {
            finishCell()
            if let currentRow, !currentRow.isEmpty {
                rows.append(currentRow)
            }
            currentRow = nil
        }

        for match in matches {
            if match.range.location > previousEnd {
                appendContent(string.substring(with: NSRange(
                    location: previousEnd,
                    length: match.range.location - previousEnd
                )))
            }
            previousEnd = NSMaxRange(match.range)
            let isClosing = !group(1, in: match, source: string).isEmpty
            let tag = group(2, in: match, source: string).lowercased()
            let attributes = parseHTMLAttributes(group(3, in: match, source: string))

            switch tag {
            case "caption":
                if isClosing {
                    title = caption.map(sanitizeInlineHTML)?.nilIfEmpty
                    caption = nil
                } else {
                    caption = ""
                }
            case "tr":
                if isClosing {
                    finishRow()
                } else {
                    finishRow()
                    currentRow = []
                }
            case "td", "th":
                if isClosing {
                    finishCell()
                } else if currentRow != nil {
                    finishCell()
                    currentCell = HTMLCellDraft(
                        isHeader: tag == "th" || attributes.keys.contains("header"),
                        alignment: parseHTMLAlignment(attributes),
                        verticalAlignment: parseHTMLVerticalAlignment(attributes["valign"]),
                        columnSpan: parseHTMLSpan(attributes["colspan"]),
                        rowSpan: parseHTMLSpan(attributes["rowspan"])
                    )
                }
            case "br":
                if !isClosing { appendContent("\n") }
            default:
                break
            }
        }
        if previousEnd < string.length {
            appendContent(string.substring(from: previousEnd))
        }
        finishRow()

        guard !rows.isEmpty else { return nil }
        let borderValue = tableAttributes["border"]
        let isBordered = borderValue.map {
            $0 != "0" && $0.caseInsensitiveCompare("false") != .orderedSame
        } ?? false
        let isStriped = tableAttributes["class"]?
            .components(separatedBy: .whitespacesAndNewlines)
            .contains(where: { $0.caseInsensitiveCompare("striped") == .orderedSame }) ?? false
        return AgentMessageTable(
            rows: rows,
            title: title,
            isBordered: isBordered,
            isStriped: isStriped
        )
    }

    private static func parseHTMLAttributes(_ source: String) -> [String: String] {
        let string = source as NSString
        let matches = htmlAttributeExpression.matches(
            in: source,
            range: NSRange(location: 0, length: string.length)
        )
        var attributes: [String: String] = [:]
        for match in matches {
            let value = (2...4)
                .map { group($0, in: match, source: string) }
                .first(where: { !$0.isEmpty }) ?? ""
            attributes[group(1, in: match, source: string).lowercased()] = decodeHTMLEntities(value)
        }
        return attributes
    }

    private static func parseHTMLAlignment(
        _ attributes: [String: String]
    ) -> AgentMessageTableAlignment {
        let alignment = attributes["align"] ?? attributes["style"]
            .map { style in
                let lowercased = style.lowercased()
                guard let propertyRange = lowercased.range(of: "text-align"),
                      let colon = lowercased[propertyRange.upperBound...].firstIndex(of: ":") else { return "" }
                return lowercased[lowercased.index(after: colon)...]
                    .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init) ?? ""
            }
        switch alignment?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "center": return .center
        case "right", "end": return .end
        default: return .start
        }
    }

    private static func parseHTMLVerticalAlignment(
        _ source: String?
    ) -> AgentMessageTableVerticalAlignment {
        switch source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "middle", "center": return .middle
        case "bottom": return .bottom
        default: return .top
        }
    }

    private static func parseHTMLSpan(_ source: String?) -> Int {
        min(max(Int(source ?? "") ?? 1, 1), 32)
    }

    private static func sanitizeInlineHTML(_ source: String) -> String {
        var result = replacingMatches(in: source, expression: htmlLinkExpression) { match, string in
            let label = group(2, in: match, source: string)
            let attributes = parseHTMLAttributes(group(1, in: match, source: string))
            let href = sanitizeHTMLHref(attributes["href"] ?? "")
            if href.isEmpty { return label }
            if label.trimmingCharacters(in: .whitespacesAndNewlines) == href { return href }
            return "\(label) (\(href))"
        }
        result = replacingMatches(in: result, expression: htmlBoldExpression) {
            "**\(group(1, in: $0, source: $1))**"
        }
        result = replacingMatches(in: result, expression: htmlItalicExpression) {
            "*\(group(1, in: $0, source: $1))*"
        }
        result = replacingMatches(in: result, expression: htmlCodeExpression) {
            "`\(group(1, in: $0, source: $1))`"
        }
        result = htmlBreakExpression.stringByReplacingMatches(
            in: result,
            range: NSRange(location: 0, length: (result as NSString).length),
            withTemplate: "\n"
        )
        result = htmlTagExpression.stringByReplacingMatches(
            in: result,
            range: NSRange(location: 0, length: (result as NSString).length),
            withTemplate: ""
        )
        return decodeHTMLEntities(result).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeHTMLHref(_ source: String) -> String {
        let href = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: href),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "mytonwallet", "mtw", "gramwallet"].contains(scheme) else {
            return ""
        }
        return href
    }

    private static func fencedCodeBlockRanges(in source: String) -> [NSRange] {
        let string = source as NSString
        var ranges: [NSRange] = []
        var activeFence: ActiveCodeFence?
        var location = 0

        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
            if let marker = codeFenceMarker(in: line) {
                if let currentFence = activeFence {
                    if isClosingFence(marker, for: currentFence) {
                        ranges.append(NSRange(
                            location: currentFence.startLocation,
                            length: NSMaxRange(lineRange) - currentFence.startLocation
                        ))
                        activeFence = nil
                    }
                } else {
                    activeFence = ActiveCodeFence(
                        character: marker.character,
                        length: marker.length,
                        startLocation: lineRange.location
                    )
                }
            }
            location = NSMaxRange(lineRange)
        }

        if let activeFence {
            ranges.append(NSRange(
                location: activeFence.startLocation,
                length: string.length - activeFence.startLocation
            ))
        }
        return ranges
    }

    private static func updateCodeFenceState(
        for line: String,
        activeFence: inout ActiveCodeFence?
    ) -> Bool {
        guard let marker = codeFenceMarker(in: line) else { return false }
        if let currentFence = activeFence {
            guard isClosingFence(marker, for: currentFence) else { return false }
            activeFence = nil
        } else {
            activeFence = ActiveCodeFence(
                character: marker.character,
                length: marker.length,
                startLocation: 0
            )
        }
        return true
    }

    private static func codeFenceMarker(in line: String) -> CodeFenceMarker? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let content = line.dropFirst(indentation)
        guard let character = content.first, character == "`" || character == "~" else {
            return nil
        }
        let markerLength = content.prefix(while: { $0 == character }).count
        guard markerLength >= 3 else { return nil }
        return CodeFenceMarker(
            character: character,
            length: markerLength,
            remainder: String(content.dropFirst(markerLength))
        )
    }

    private static func isClosingFence(
        _ marker: CodeFenceMarker,
        for activeFence: ActiveCodeFence
    ) -> Bool {
        marker.character == activeFence.character
            && marker.length >= activeFence.length
            && marker.remainder.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func decodeHTMLEntities(_ source: String) -> String {
        let named = source
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
        return replacingMatches(in: named, expression: numericHTMLEntityExpression) { match, string in
            let hex = group(1, in: match, source: string)
            let decimal = group(2, in: match, source: string)
            let value = !hex.isEmpty ? Int(hex, radix: 16) : Int(decimal)
            guard let value, let scalar = UnicodeScalar(value) else {
                return string.substring(with: match.range)
            }
            return String(Character(scalar))
        }
    }

    private static func expression(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            preconditionFailure("Invalid static regular expression: \(pattern)")
        }
        return expression
    }

    private static func group(
        _ index: Int,
        in match: NSTextCheckingResult,
        source: NSString
    ) -> String {
        guard index < match.numberOfRanges else { return "" }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return "" }
        return source.substring(with: range)
    }

    private static func replacingMatches(
        in source: String,
        expression: NSRegularExpression,
        transform: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        let original = source as NSString
        let matches = expression.matches(
            in: source,
            range: NSRange(location: 0, length: original.length)
        )
        var result = source as NSString
        for match in matches.reversed() {
            result = result.replacingCharacters(
                in: match.range,
                with: transform(match, original)
            ) as NSString
        }
        return result as String
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
