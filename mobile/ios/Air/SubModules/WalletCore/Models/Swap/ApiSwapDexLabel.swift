
public enum ApiSwapDexLabel: String, Codable, Sendable {
    case dedust = "dedust"
    case ston = "ston"
    case jupiter = "jupiter"
    
    public var displayName: String {
        switch self {
        case .dedust:
            "DeDust"
        case .ston:
            "STON.fi"
        case .jupiter:
            "Jupiter"
        }
    }
}
