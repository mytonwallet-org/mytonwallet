
import Foundation

private let log = Log("Task")

public func withRetries<T>(_ count: Int, f: () async throws -> T, handleError: ((any Error) async throws -> ())? = nil) async throws -> T {
    if count >= 1 {
        for i in 0..<count {
            try await Task.sleep(for: .seconds(Double(i) * 0.5))
            do {
                return try await f()
            } catch {
                if let handleError {
                    try await handleError(error)
                } else {
                    log.info("\(error)")
                }
            }
            try Task.checkCancellation()
        }
    }
    return try await f()
}
