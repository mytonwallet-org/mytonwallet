import UIKit
import WalletCore

/// Selected home-card appearance; custom profiles apply to both wallet brands.
public struct CardMotionPreset: Equatable, Sendable {
    var angle: Double = 12
    var releaseFrequency: Double = 13.9529
    var shineEnabled: Bool = false
    var shineOpacity: Float = 0.3
    var linearBlur: Float = 70
    var improvedShine: Bool = true
    var experimentalShine: Bool = true
    var borderShine: Bool = true
    var blueBorderShine: Bool = false
    var gramWidth: Float = 120
    var gramOpacity: Float = 0.24
    var gramBlur: Float = 18
    var gramReflectionMode: CardGramReflectionMode = .current
    var gramTelegramShine: Bool = false
    var gramStarGrowth: Bool = false
    var gramStarBlend: Int = 0
    var gramStarSizeIn: Float = 1.1
    var gramStarSizeOut: Float = 0.65
    var gramStarOpacityIn: Float = 1
    var gramStarOpacityOut: Float = 1
    var gramV2MaxRotation: Double = 35
    var gramV2Sensitivity: Double = 1
    var materialEnabled: Bool = true
    var materialEnvironment: Int = 0
    var materialPreset: Int = 0
    var materialIntensity: Float = 0.28
    var materialBevel: Float = 0.4
    var materialEmboss: Float = 0.4
    var materialDepth: Float = 3.5
    var touchGlow: Bool = true
    var touchGlowIntensity: Float = 0.7
    var touchGlowArea: Float = 0.4
    var touchGlowBlur: Float = 24
    var touchGlowGradualAppearance: Bool = true
    var touchGlowAppearanceDuration: Double = 0.67
    var holdToPlay: Bool = true
    var holdDelay: Double = 0.15

    public static func home(nft: ApiNft?, artwork: CardSurfaceConfiguration.DefaultArtwork = CardSurfaceConfiguration.current.defaultArtwork) -> Self {
        if let nft, nft.isMtwCard {
            switch nft.metadata?.mtwCardType {
            case .silver: return .silver
            case .gold: return .gold
            case .platinum: return .platinum
            case .black: return .black
            case .standard, nil: return .standard
            }
        }
        return artwork == .gramWallet ? .gramDefault : .myDefault
    }

    static let gramDefault: Self = {
        var preset = Self()
        preset.borderShine = false
        preset.experimentalShine = false
        preset.gramOpacity = 0.33
        preset.gramReflectionMode = .telegramV2
        preset.gramStarBlend = 1
        preset.gramStarGrowth = true
        preset.gramStarOpacityOut = 0.5
        preset.gramStarSizeIn = 1
        preset.gramStarSizeOut = 0.5
        preset.gramTelegramShine = true
        preset.gramV2MaxRotation = 180
        preset.improvedShine = false
        preset.linearBlur = 0
        preset.materialIntensity = 0
        preset.shineEnabled = true
        preset.shineOpacity = 0.14
        return preset
    }()

    static let myDefault: Self = {
        let preset = Self()
        return preset
    }()

    static let standard: Self = {
        var preset = Self()
        preset.materialIntensity = 0.62
        return preset
    }()

    static let silver: Self = {
        var preset = Self()
        preset.materialIntensity = 0.62
        preset.materialPreset = 1
        return preset
    }()

    static let gold: Self = {
        var preset = Self()
        preset.materialIntensity = 0.48
        preset.materialPreset = 1
        return preset
    }()

    static let platinum: Self = {
        var preset = Self()
        preset.materialIntensity = 0.22
        preset.materialPreset = 1
        return preset
    }()

    static let black: Self = {
        var preset = Self()
        preset.materialIntensity = 0.22
        preset.materialPreset = 2
        return preset
    }()

    @MainActor func configure(_ driver: CardSurfaceMotionDriver, surface: CardSurfaceConfiguration) {
        driver.input = .device
        driver.pressDepth = angle / 8
        driver.releaseFrequency = releaseFrequency
        driver.shineStyle = surface.shine
        driver.shineEnabled = shineEnabled
        driver.gramReflectionMode = gramReflectionMode
        driver.gramV2MaxRotation = gramV2MaxRotation
        driver.gramV2Sensitivity = gramV2Sensitivity
        driver.continuousCrystalShineEnabled = experimentalShine && surface.shine == .linear
        driver.improvedLinearBehavior = improvedShine
        driver.borderShineEnabled = borderShine || materialEnabled
        driver.touchSpotEnabled = touchGlow
        driver.touchSpotGradualAppearance = touchGlowGradualAppearance
        driver.touchSpotAppearanceDelay = holdDelay
        driver.touchSpotAppearanceDuration = touchGlowAppearanceDuration
    }

    @MainActor public func applyContentLight(_ light: CardSurfaceLight, balance: UIView, change: MtwCardChangeView, accountLine: MtwCardAccountLineView, decoration: UIView) {
        let environment = CardBackgroundAnimationEnvironment.shared
        let enabled = materialEnabled && environment.cardEffectsEnabled && environment.animationsEnabled
            && !environment.reduceMotion && !environment.lowPowerMode
        let tilt = light.borderTilt ?? light.tilt
        let depth = enabled ? CGFloat(materialDepth) : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Animate the existing planes without asking UIKit to lay out every glyph.
        let foreground = CGAffineTransform(translationX: tilt.x * depth * 1.1, y: tilt.y * depth * 1.1)
        balance.layer.setAffineTransform(foreground)
        change.layer.setAffineTransform(foreground)
        accountLine.layer.setAffineTransform(CGAffineTransform(translationX: tilt.x * depth * 0.8, y: tilt.y * depth * 0.8))
        decoration.layer.setAffineTransform(CGAffineTransform(translationX: tilt.x * depth * 0.4, y: tilt.y * depth * 0.4))
        // An offset shadow of this masked line duplicates every glyph. Keep its
        // depth translation, and put the material lighting on the badge only.
        change.setMaterialLight(tilt: enabled ? tilt : .zero, emboss: enabled ? CGFloat(materialEmboss) : 0)
        accountLine.layer.shadowOpacity = 0
        accountLine.setMaterialLight(tilt: enabled ? tilt : .zero, emboss: enabled ? CGFloat(materialEmboss) : 0)
        for view in [decoration] {
            view.layer.shadowColor = UIColor.white.cgColor
            view.layer.shadowOffset = CGSize(width: -tilt.x * 1.2, height: -tilt.y * 1.2 - 0.35)
            view.layer.shadowRadius = 0.45
            view.layer.shadowOpacity = enabled ? materialEmboss * 0.7 : 0
        }
        CATransaction.commit()
    }
}
