import WalletContext

public enum CardBlobMotion: UInt32, Sendable, CaseIterable {
    case anchorOrbit, cardCenter
}

public struct CardSurfaceConfiguration: Equatable, Sendable {
    public enum Shine: UInt32, Sendable { case linear, radial }
    public enum DefaultArtwork: UInt32, Sendable { case myWallet, gramWallet }

    public var shine: Shine
    public var shineOpacity: Float
    /// Full width at half maximum, as a fraction of the card width.
    public var linearWidth: Float
    /// Degrees above horizontal, rising from bottom left to top right.
    public var linearAngle: Float = 61
    public var radialBrush: Bool
    public var touchSpotEnabled = false
    public var blobMotion: CardBlobMotion = .cardCenter
    public var defaultArtwork: DefaultArtwork = .myWallet

    public static let myWallet = Self(shine: .linear, shineOpacity: 0.14, linearWidth: 0.28, radialBrush: false)
    public static let gramWallet = Self(shine: .radial, shineOpacity: 0.24, linearWidth: 0.14, radialBrush: true, defaultArtwork: .gramWallet)
    public static var current: Self { IS_GRAM_WALLET ? .gramWallet : .myWallet }

    public func forArtwork(isCustom: Bool) -> Self {
        guard isCustom else { return self }
        var result = self
        result.radialBrush = false
        return result
    }
}
