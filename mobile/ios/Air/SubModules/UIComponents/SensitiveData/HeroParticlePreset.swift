import UIKit
import WalletCore
import Combine

extension CardParticleSettings {
    /// Selected in Motion Lab; shared by both wallets and every hero amount.
    static let hero = CardParticleSettings(size: 2.2, frequency: 0.75, spread: 24,
        effect: .disintegrate, disintegration: CardDisintegrationSettings(
            hideDuration: 0.7, revealDuration: 0.6, travel: 10, lift: 0,
            originInfluence: 1, destinationMix: 0.2, turbulence: 1, stagger: 0.2,
            timingRandomness: 0, rotation: 40, fragmentSize: 1.6, finalSize: 0.7,
            easing: 1, blendStart: 0.1, blendDuration: 0.65))
}

@MainActor
enum HeroParticleAnimationPolicy {
    enum TransitionMode { case particles, crossfade, instant }

    static func transitionMode(animations: Bool, lowPower: Bool, reduceMotion: Bool, applicationActive: Bool) -> TransitionMode {
        guard animations, !reduceMotion, applicationActive else { return .instant }
        return lowPower ? .crossfade : .particles
    }

    static var transitionMode: TransitionMode {
        let environment = CardBackgroundAnimationEnvironment.shared
        return transitionMode(animations: AppStorageHelper.animations, lowPower: environment.lowPowerMode,
            reduceMotion: UIAccessibility.isReduceMotionEnabled, applicationActive: environment.applicationActive)
    }

    static var allowsAnimation: Bool {
        transitionMode == .particles
    }

    static func observe(_ update: @escaping () -> Void) -> AnyCancellable {
        CardBackgroundAnimationEnvironment.shared.objectWillChange
            .receive(on: RunLoop.main).sink { update() }
    }
}
