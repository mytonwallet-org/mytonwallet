extension String {
    var svgURLReferenceId: String? {
        let prefix = "url(#"
        guard hasPrefix(prefix), hasSuffix(")") else {
            return nil
        }

        return String(dropFirst(prefix.count).dropLast())
    }
}
