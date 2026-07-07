
import Foundation

public struct DisplayError: Error {
    
    public var title: String?
    public var text: String
    
    public init(title: String? = nil, text: String) {
        self.title = title
        self.text = text
    }
}

extension DisplayError: LocalizedError {
    public var errorDescription: String? {
        text
    }
}
