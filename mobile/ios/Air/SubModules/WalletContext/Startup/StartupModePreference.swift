import Foundation

public enum StartupMode: String, Equatable, Sendable {
    case air
    case classic

    public var isAir: Bool {
        self == .air
    }

    public init(isAir: Bool) {
        self = isAir ? .air : .classic
    }
}

public enum StartupModeDecisionReason: String, Equatable, Sendable {
    case storedPreference
    case defaultPreference
    case preferenceUpdated
    case missingFirstLaunchMarkerDefaultedToAir
    case missingFirstLaunchMarkerPreservedPreference
    case classicUnavailable
    case forcedAir
}

public struct StartupModeDecision: Equatable, Sendable {
    public let mode: StartupMode
    public let reason: StartupModeDecisionReason

    public init(mode: StartupMode, reason: StartupModeDecisionReason) {
        self.mode = mode
        self.reason = reason
    }

    public var traceDetails: String {
        "reason=\(reason.rawValue) mode=\(mode.rawValue) isOnAir=\(mode.isAir)"
    }
}

public struct StartupModePreference {
    private static let storageKey = "isOnAir"

    private let defaults: UserDefaults
    private let defaultMode: StartupMode

    public init(
        defaults: UserDefaults = .standard,
        defaultMode: StartupMode = DEFAULT_TO_AIR ? .air : .classic
    ) {
        self.defaults = defaults
        self.defaultMode = defaultMode
    }

    public func storedMode() -> StartupMode? {
        (defaults.object(forKey: Self.storageKey) as? Bool).map(StartupMode.init(isAir:))
    }

    @discardableResult
    public func setMode(_ mode: StartupMode, canUseClassic: Bool) -> StartupModeDecision {
        guard canUseClassic || mode == .air else {
            persist(.air)
            return StartupModeDecision(mode: .air, reason: .classicUnavailable)
        }
        persist(mode)
        return StartupModeDecision(mode: mode, reason: .preferenceUpdated)
    }

    @discardableResult
    public func forceAir() -> StartupModeDecision {
        persist(.air)
        return StartupModeDecision(mode: .air, reason: .forcedAir)
    }

    public func currentMode(canUseClassic: Bool) -> StartupModeDecision {
        guard canUseClassic else {
            persist(.air)
            return StartupModeDecision(mode: .air, reason: .classicUnavailable)
        }
        if let storedMode = storedMode() {
            return StartupModeDecision(mode: storedMode, reason: .storedPreference)
        }
        return StartupModeDecision(mode: defaultMode, reason: .defaultPreference)
    }

    @discardableResult
    public func applyMissingFirstLaunchMarkerPolicy(canUseClassic: Bool) -> StartupModeDecision {
        guard canUseClassic else {
            persist(.air)
            return StartupModeDecision(mode: .air, reason: .classicUnavailable)
        }
        if let storedMode = storedMode() {
            return StartupModeDecision(mode: storedMode, reason: .missingFirstLaunchMarkerPreservedPreference)
        }
        persist(.air)
        return StartupModeDecision(mode: .air, reason: .missingFirstLaunchMarkerDefaultedToAir)
    }

    private func persist(_ mode: StartupMode) {
        defaults.set(mode.isAir, forKey: Self.storageKey)
    }
}
