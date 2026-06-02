import Foundation

enum AccountTitle {
    static func normalized(_ title: String?) -> String? {
        guard let title else {
            return nil
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }
}
