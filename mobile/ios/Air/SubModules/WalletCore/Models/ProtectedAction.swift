import Foundation

public enum ProtectedActionCompletionBehavior: Sendable {
    case popAuth
    case keepAuthForReplacement
}

public enum ProtectedActionPresentationStyle: Sendable {
    case push
    case sheet
}
