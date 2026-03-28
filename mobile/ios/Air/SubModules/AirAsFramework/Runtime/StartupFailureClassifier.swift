import Foundation
import GRDB
import WalletCore
import WalletContext

enum StartupFailureClassifier {
    private static let lowDiskSpaceThresholdBytes: Int64 = 100 * 1024 * 1024

    static func classify(_ error: any Error, phase: StartupFailurePhase) -> StartupFailure {
        let rootError = StartupFailureDiagnostics.rootCause(error)
        let kind: StartupFailureKind
        if isOutOfDiskSpace(rootError) {
            kind = .outOfDiskSpace
        } else if isLegacyDataCorruption(rootError) {
            kind = .legacyDataCorruption
        } else if isDatabaseFailure(rootError) {
            kind = .databaseFailure
        } else if isStorageWriteFailure(rootError) {
            kind = .storageWriteFailed
        } else if rootError is BridgeCallError {
            kind = .bridgeFailure
        } else {
            kind = .unknown
        }

        let title = lang("Error")
        let technicalCode = "\(phase.rawValue).\(kind.rawValue)"
        let message: String
        switch kind {
        case .outOfDiskSpace:
            message = "There's not enough free storage space on your iPhone to start safely. Free up some space and try again."
        case .storageWriteFailed:
            message = "Couldn't save wallet data safely during startup. No automatic recovery action was taken. If this keeps happening, please export logs and contact support."
        case .legacyDataCorruption:
            message = "Stored wallet data looks damaged, so MyTonWallet couldn't continue safely. If this keeps happening, please export logs and contact support."
        case .databaseFailure:
            message = "MyTonWallet couldn't open its local wallet database safely. If this keeps happening, please export logs and contact support."
        case .bridgeFailure:
            message = "MyTonWallet couldn't finish wallet startup safely. If this keeps happening, please export logs and contact support."
        case .unknown:
            message = "MyTonWallet couldn't start safely. If this keeps happening, please export logs and contact support."
        }

        return StartupFailure(
            phase: phase,
            kind: kind,
            title: title,
            message: message,
            technicalCode: technicalCode,
            detailsText: StartupFailureDiagnostics.userFacingDetails(
                error,
                phase: phase,
                kind: kind,
                technicalCode: technicalCode
            )
        )
    }

    private static func isOutOfDiskSpace(_ error: any Error) -> Bool {
        if let databaseError = error as? DatabaseError {
            if databaseError.resultCode == .SQLITE_FULL || databaseError.extendedResultCode == .SQLITE_FULL {
                return true
            }
        }

        for nsError in StartupFailureDiagnostics.errorChain(error) {
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
                return true
            }
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(POSIXErrorCode.ENOSPC.rawValue) {
                return true
            }
        }

        guard let webViewDetails = StartupFailureDiagnostics.webViewStorageDetails(error) else {
            return false
        }
        if webViewDetails.localizedCaseInsensitiveContains("quotaexceeded") {
            if let available = StartupFailureDiagnostics.availableDiskBytes() {
                return available <= lowDiskSpaceThresholdBytes
            }
        }
        return false
    }

    private static func isLegacyDataCorruption(_ error: any Error) -> Bool {
        switch error {
        case GlobalStorageError.localStorageIsInvalidJson,
            GlobalStorageError.localStorageIsNotAString,
            GlobalStorageError.localStorageIsNull,
            GlobalStorageError.localStorageIsEmpty,
            GlobalMigrationError.stateVersionIsNil,
            GlobalMigrationError.stateVersionTooOld,
            is DecodingError:
            return true
        default:
            return false
        }
    }

    private static func isDatabaseFailure(_ error: any Error) -> Bool {
        guard let databaseError = error as? DatabaseError else {
            return false
        }
        switch databaseError.resultCode {
        case .SQLITE_CORRUPT, .SQLITE_NOTADB, .SQLITE_CANTOPEN, .SQLITE_IOERR, .SQLITE_READONLY, .SQLITE_SCHEMA:
            return true
        default:
            return false
        }
    }

    private static func isStorageWriteFailure(_ error: any Error) -> Bool {
        switch error {
        case GlobalStorageError.localStorageSetItemError,
            GlobalStorageError.localStorageReadbackFailed,
            GlobalStorageError.serializedValueIsNotAValidDict,
            GlobalStorageError.serializationError:
            return true
        default:
            return false
        }
    }
}
