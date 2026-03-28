import Foundation

enum StartupFailurePhase: String, Sendable {
    case databaseBootstrap
    case walletCoreBootstrap
}

enum StartupFailureKind: String, Sendable {
    case outOfDiskSpace
    case storageWriteFailed
    case legacyDataCorruption
    case databaseFailure
    case bridgeFailure
    case unknown
}

struct StartupFailure: Sendable {
    let phase: StartupFailurePhase
    let kind: StartupFailureKind
    let title: String
    let message: String
    let technicalCode: String
    let detailsText: String
}
