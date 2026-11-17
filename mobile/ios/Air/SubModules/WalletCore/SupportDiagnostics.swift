import Foundation
import WalletContext
import ZIPFoundation

private let log = Log("SupportDiagnostics")

@MainActor
public enum SupportDiagnostics {
    public static let supportURL = URL(string: "https://t.me/\(SUPPORT_USERNAME)")!

    public static func prepareLogsExportFile() async throws -> URL {
        let diagnosticsData = await collectDiagnostics()
        let sdkLogs = await collectSDKLogs()
        let nativeLogsURL = try await LogStore.shared.exportFile()
        defer { try? FileManager.default.removeItem(at: nativeLogsURL) }

        return try SupportDiagnosticsArchive.create(
            nativeLogsURL: nativeLogsURL,
            diagnosticsData: diagnosticsData,
            sdkLogsData: sdkLogs.data,
            sdkLogsError: sdkLogs.error
        )
    }

    private static func collectDiagnostics() async -> Data {
        let diagnostics = await captureCurrentState()
        do {
            return try SupportDiagnosticsArchive.encodeDiagnostics(diagnostics)
        } catch {
            log.error("failed to encode diagnostics: \(error, .public)")
            return Data("{\"error\":\"diagnostics encoding failed\"}\n".utf8)
        }
    }

    private static func collectSDKLogs() async -> SDKLogsCollection {
        do {
            let logs = try await Api.getLogsIfReady() ?? []
            return SDKLogsCollection(data: try SupportDiagnosticsArchive.encodeSDKLogs(logs), error: nil)
        } catch {
            log.error("failed to collect SDK logs: \(error, .public)")
            return SDKLogsCollection(data: Data("[]\n".utf8), error: String(reflecting: error))
        }
    }

    private static func captureCurrentState() async -> SupportDiagnosticsReport {
        log.info("support diagnostics export requested")
        let report = await SupportDiagnosticsReport.collect()
        logAppAndDeviceState(report)
        logKeychainState(report)
        logAccountState(report)
        logSecurityState(report)
        return report
    }

    private static func logAppAndDeviceState(_ report: SupportDiagnosticsReport) {
        log.info("app and device state:")
        log.info("app=\(report.app.name, .public) version=\(report.app.version, .public)")
        log.info("build=\(report.app.build, .public) distribution=\(report.app.distribution, .public)")
        log.info("bundle=\(report.app.bundleIdentifier, .public)")
        log.info("device=\(report.device.hardwareModel, .public) family=\(report.device.deviceFamily, .public)")
        log.info("system=\(report.device.systemName, .public) \(report.device.systemVersion, .public)")
        log.info("locale=\(report.device.localeIdentifier, .public) timeZone=\(report.device.timeZone, .public)")
    }

    private static func logKeychainState(_ report: SupportDiagnosticsReport) {
        log.info("keychain state:")
        log.info("keys = \(report.installation.keychainKeys, .public)")
        log.info("stateVersion = \(report.installation.stateVersion as Any, .public)")
        log.info("keychain currentAccountId = \(report.installation.keychainCurrentAccountId as Any, .public)")
        log.info("clientId = \(report.installation.clientId as Any, .public)")
        log.info("baseCurrency = \(report.installation.baseCurrency as Any, .public)")
        log.info("credentials state = \(report.security.credentials.state, .public)")
        log.info("credentials has username = \(report.security.credentials.hasUsername as Any, .public)")
        log.info("credentials password length = \(report.security.credentials.passwordLength as Any, .public)")
        log.info("credentials valid format = \(report.security.credentials.hasValidPasscodeFormat as Any, .public)")
        if let error = report.security.credentials.error {
            log.error("credentials inspection failed: \(error, .public)")
        }
    }

    private static func logAccountState(_ report: SupportDiagnosticsReport) {
        log.info("account state:")
        log.info("currentAccountId = \(report.accounts.currentAccountId as Any, .public)")
        log.info("orderedAccountIds = #\(report.accounts.orderedAccountIds.count) \(report.accounts.orderedAccountIds, .public)")
        log.info("databaseAccountIds = #\(report.accounts.databaseAccountIds.count) \(report.accounts.databaseAccountIds, .public)")
        log.info("keychainAccountIds = \(report.accounts.keychainAccountIds as Any, .public)")
        for account in report.accounts.items {
            log.info("accountId=\(account.id, .public) isMfaEnabled=\(account.isMfaEnabled as Any, .public)")
        }
        if report.accounts.health.issues.isEmpty {
            log.info("account health = \(report.accounts.health.status, .public)")
        } else {
            log.fault(
                "account health = \(report.accounts.health.status, .public) issues=\(report.accounts.health.issues, .public)"
            )
        }
    }

    private static func logSecurityState(_ report: SupportDiagnosticsReport) {
        log.info("secret migration state:")
        log.info("legacy ciphertext ids=\(report.security.legacyCiphertextAccountIds, .public)")
        log.info("malformed legacy secret ids=\(report.security.malformedLegacySecretAccountIds, .public)")
        log.info("enclave configuredAuthTypes=\(report.security.configuredAuthTypes, .public)")
        log.info("legacyMigrationAllowed=\(report.security.isLegacyMigrationAllowed)")
        log.info("enclave present ids=\(report.security.enclaveSecretAccountIds as Any, .public)")
        log.info("enclave missing ids=\(report.security.missingEnclaveSecretAccountIds as Any, .public)")
        for (inspection, error) in report.security.inspectionErrors.sorted(by: { $0.key < $1.key }) {
            log.error("\(inspection, .public) inspection failed: \(error, .public)")
        }
    }
}

private struct SDKLogsCollection {
    let data: Data
    let error: String?
}

struct SupportDiagnosticsArchive {
    static let nativeLogsFilename = "native-logs.tsv"
    static let diagnosticsFilename = "diagnostics.json"
    static let sdkLogsFilename = "sdk-logs.json"
    static let sdkLogsErrorFilename = "sdk-logs-error.txt"

    static func encodeDiagnostics<T: Encodable>(_ diagnostics: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(diagnostics) + Data("\n".utf8)
    }

    static func encodeSDKLogs(_ logs: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(logs) else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        return try JSONSerialization.data(
            withJSONObject: logs,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) + Data("\n".utf8)
    }

    static func create(
        nativeLogsURL: URL,
        diagnosticsData: Data,
        sdkLogsData: Data,
        sdkLogsError: String?,
        destinationDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) throws -> URL {
        let stagingDirectory = fileManager.temporaryDirectory
            .appending(component: "air-logs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        try fileManager.copyItem(
            at: nativeLogsURL,
            to: stagingDirectory.appending(component: nativeLogsFilename)
        )
        try diagnosticsData.write(
            to: stagingDirectory.appending(component: diagnosticsFilename),
            options: .atomic
        )
        try sdkLogsData.write(
            to: stagingDirectory.appending(component: sdkLogsFilename),
            options: .atomic
        )
        if let sdkLogsError {
            try Data("\(sdkLogsError)\n".utf8).write(
                to: stagingDirectory.appending(component: sdkLogsErrorFilename),
                options: .atomic
            )
        }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let archiveURL = destinationDirectory.appending(component: "air-logs-\(timestamp).zip")
        try fileManager.zipItem(
            at: stagingDirectory,
            to: archiveURL,
            shouldKeepParent: false,
            compressionMethod: .deflate
        )
        return archiveURL
    }
}
