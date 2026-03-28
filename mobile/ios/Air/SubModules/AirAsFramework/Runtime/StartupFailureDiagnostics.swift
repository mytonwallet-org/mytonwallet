import Foundation
import WalletCore
import WalletContext

enum StartupFailureDiagnostics {
    static func diagnosticsReport(_ error: any Error, failure: StartupFailure) -> String {
        let errorType = String(reflecting: type(of: error))
        let rootError = rootCause(error)
        let rootErrorType = String(reflecting: type(of: rootError))
        let context = startupContextDetails(error)
        let chain = errorChain(rootError)
            .map { "\($0.domain):\($0.code):\($0.localizedDescription)" }
            .joined(separator: " -> ")
        let dbDetails = databaseDetails()
        let diskDetails = diskDetails()
        let webViewDetails = webViewStorageDetails(rootError)
        return [
            "startup failure",
            "phase=\(failure.phase.rawValue)",
            "kind=\(failure.kind.rawValue)",
            "code=\(failure.technicalCode)",
            "type=\(errorType)",
            "rootType=\(rootErrorType)",
            "error=\(String(describing: error))",
            "context=\(context ?? "none")",
            "chain=\(chain.isEmpty ? "none" : chain)",
            "db=\(dbDetails)",
            "disk=\(diskDetails)",
            "keychainAccounts=\(keychainAccountCount())",
            "webView=\(webViewDetails ?? "none")",
        ].joined(separator: " | ")
    }

    static func userFacingDetails(
        _ error: any Error,
        phase: StartupFailurePhase,
        kind: StartupFailureKind,
        technicalCode: String
    ) -> String {
        let rootError = rootCause(error)
        let nsError = errorChain(rootError).first
        var lines = [
            "Technical code: \(technicalCode)",
            "Phase: \(userFacingPhaseName(phase))",
            "Category: \(userFacingKindName(kind))",
            "Error type: \(String(reflecting: type(of: rootError)))",
            "Database: \(userFacingDatabaseDetails())",
            "Free space: \(userFacingDiskDetails())",
            "Keychain accounts: \(keychainAccountCount())",
        ]

        if let nsError {
            lines.append("NSError: \(nsError.domain) (\(nsError.code))")
        }
        if let context = startupContextDetails(error) {
            lines.append("Context: \(context)")
        }
        if let webViewDetails = webViewStorageDetails(rootError)?.nilIfEmpty {
            lines.append("Storage: \(truncated(webViewDetails, limit: 180))")
        }
        return lines.joined(separator: "\n")
    }

    static func errorChain(_ error: any Error) -> [NSError] {
        var result: [NSError] = []
        var current: NSError? = error as NSError
        var visited = Set<String>()
        while let currentError = current, result.count < 8 {
            let key = "\(currentError.domain)#\(currentError.code)#\(currentError.localizedDescription)"
            if visited.contains(key) {
                break
            }
            visited.insert(key)
            result.append(currentError)
            if let underlying = currentError.userInfo[NSUnderlyingErrorKey] as? NSError {
                current = underlying
            } else {
                current = nil
            }
        }
        return result
    }

    static func rootCause(_ error: any Error) -> any Error {
        var current = error
        var depth = 0
        while depth < 8,
              let contextualError = current as? any StartupContextError,
              let underlyingError = contextualError.underlyingStartupError
        {
            current = underlyingError
            depth += 1
        }
        return current
    }

    static func startupContextDetails(_ error: any Error) -> String? {
        var details: [String] = []
        var current = error
        var depth = 0
        while depth < 8, let contextualError = current as? any StartupContextError {
            details.append(contextualError.startupContextDescription)
            guard let underlyingError = contextualError.underlyingStartupError else {
                break
            }
            current = underlyingError
            depth += 1
        }
        return details.joined(separator: " | ").nilIfEmpty
    }

    static func availableDiskBytes() -> Int64? {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        if let important = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(important)
        }
        if let available = values?.volumeAvailableCapacity {
            return Int64(available)
        }
        return nil
    }

    static func webViewStorageDetails(_ error: any Error) -> String? {
        switch error {
        case let GlobalStorageError.localStorageSetItemError(rawMessage):
            guard let data = rawMessage.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(WebViewStorageErrorPayload.self, from: data)
            else {
                return rawMessage
            }

            return [payload.name, payload.message, payload.description]
                .compactMap { $0?.nilIfEmpty }
                .joined(separator: " | ")
                .nilIfEmpty
        case let GlobalStorageError.localStorageReadbackFailed(details):
            return details
        default:
            return nil
        }
    }

    private static func databaseDetails() -> String {
        let path = dbUrl.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return "missing path=\(path)"
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? nil
        if let size {
            return "path=\(path) size=\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        } else {
            return "path=\(path) size=unknown"
        }
    }

    private static func diskDetails() -> String {
        guard let available = availableDiskBytes() else {
            return "available=unknown"
        }
        return "available=\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))"
    }

    private static func userFacingDatabaseDetails() -> String {
        let path = dbUrl.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return "Missing"
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? nil
        if let size {
            return "Present, \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        } else {
            return "Present, size unknown"
        }
    }

    private static func userFacingDiskDetails() -> String {
        guard let available = availableDiskBytes() else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
    }

    private static func keychainAccountCount() -> Int {
        KeychainHelper.getAccounts()?.count ?? 0
    }

    private static func userFacingPhaseName(_ phase: StartupFailurePhase) -> String {
        switch phase {
        case .databaseBootstrap:
            return "Database bootstrap"
        case .walletCoreBootstrap:
            return "Wallet startup"
        }
    }

    private static func userFacingKindName(_ kind: StartupFailureKind) -> String {
        switch kind {
        case .outOfDiskSpace:
            return "Out of disk space"
        case .storageWriteFailed:
            return "Storage write failure"
        case .legacyDataCorruption:
            return "Legacy data corruption"
        case .databaseFailure:
            return "Database failure"
        case .bridgeFailure:
            return "Bridge failure"
        case .unknown:
            return "Unknown"
        }
    }

    private static func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        let endIndex = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<endIndex]) + "..."
    }
}

private struct WebViewStorageErrorPayload: Decodable {
    let name: String?
    let message: String?
    let description: String?
}
