
public enum StakingAccessoryContent: Equatable, Sendable {
    case active
    case inactive
}

public struct StakingBadgeContent: Equatable, Sendable {
    public var isActive: Bool
    public var yieldType: ApiYieldType
    public var yieldValue: Double
}

public struct StakingTokenPresentation: Equatable, Sendable {
    public var accessory: StakingAccessoryContent?
    public var badge: StakingBadgeContent?
}
