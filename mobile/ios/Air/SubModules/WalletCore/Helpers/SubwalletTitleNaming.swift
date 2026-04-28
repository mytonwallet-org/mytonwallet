import Foundation

enum SubwalletTitleNaming {
    static func baseTitle(from title: String) -> String {
        let suffixDigits = title.reversed().prefix { $0.isNumber }
        guard !suffixDigits.isEmpty else {
            return title
        }

        let suffixLength = suffixDigits.count
        guard let dotIndex = title.index(
            title.endIndex,
            offsetBy: -(suffixLength + 1),
            limitedBy: title.startIndex
        ), title[dotIndex] == "."
        else {
            return title
        }

        var baseTitle = String(title[..<dotIndex])
        if baseTitle.last?.isWhitespace == true {
            baseTitle.removeLast()
        }
        return baseTitle
    }

    static func nextTitle(baseTitle: String, existingTitles: [String]) -> String {
        let separator = separator(for: baseTitle)
        let separatorPattern = separator.isEmpty ? "" : " ?"
        let pattern = "^" + NSRegularExpression.escapedPattern(for: baseTitle) + separatorPattern + "\\.(\\d+)$"
        let regex = try? NSRegularExpression(pattern: pattern)

        let maxIndex = existingTitles
            .compactMap { title -> Int? in
                guard let regex else {
                    return nil
                }

                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                guard let match = regex.firstMatch(in: title, range: range),
                      match.numberOfRanges > 1,
                      let numberRange = Range(match.range(at: 1), in: title)
                else {
                    return nil
                }

                return Int(title[numberRange])
            }
            .max() ?? 0

        return "\(baseTitle)\(separator).\(max(maxIndex, 1) + 1)"
    }

    private static func separator(for baseTitle: String) -> String {
        baseTitle.last?.isNumber == true ? "" : " "
    }
}
