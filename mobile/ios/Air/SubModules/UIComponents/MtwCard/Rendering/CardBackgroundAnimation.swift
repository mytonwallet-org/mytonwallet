import Combine
import SwiftUI
import UIKit
import WalletCore

/// One set of observers for all cards, rather than observers or polling per frame.
@MainActor
public final class CardBackgroundAnimationEnvironment: ObservableObject {
    public static let shared = CardBackgroundAnimationEnvironment()
    @Published public private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published public private(set) var reduceMotion = UIAccessibility.isReduceMotionEnabled
    @Published public private(set) var applicationActive = UIApplication.shared.applicationState == .active
    @Published public private(set) var animationsEnabled = AppStorageHelper.animations
    @Published public private(set) var cardEffectsEnabled = !AppStorageHelper.is3dCardDisabled
    let willSuspend = PassthroughSubject<Void, Never>()
    private var subscriptions: Set<AnyCancellable> = []

    private init() {
        let center = NotificationCenter.default
        // Lifecycle notifications arrive on the main thread. Publish the state
        // synchronously so reconfiguration cannot restart a suspending renderer.
        center.publisher(for: UIApplication.willResignActiveNotification)
            .merge(with: center.publisher(for: UIApplication.didBecomeActiveNotification))
            .sink { [weak self] notification in
                guard let self else { return }
                let active = notification.name == UIApplication.didBecomeActiveNotification
                if active { refreshPreferences() } else { willSuspend.send() }
                applicationActive = active
            }.store(in: &subscriptions)
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, UIAccessibility.reduceMotionStatusDidChangeNotification,
                     AppStorageHelper.animationsChangedNotification, AppStorageHelper.cardEffectsChangedNotification] {
            center.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refreshPreferences() }.store(in: &subscriptions)
        }
    }

    private func refreshPreferences() {
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        animationsEnabled = AppStorageHelper.animations
        cardEffectsEnabled = !AppStorageHelper.is3dCardDisabled
    }
}

public struct CardBackgroundMotion: ViewModifier {
    public nonisolated static let defaultStrength = 15.0
    public nonisolated static let defaultSpeed = 1.55

    private let size: CGSize
    private let time: Double
    private let strength: Double
    private let seed: UInt32

    public init(size: CGSize, time: Double, strength: Double = CardBackgroundMotion.defaultStrength, seed: UInt32) {
        self.size = size
        self.time = time
        self.strength = strength
        self.seed = seed
    }

    @ViewBuilder public func body(content: Content) -> some View {
        if #available(iOS 17, *), time != 0, strength != 0 {
            content.distortionEffect(
                ShaderLibrary.bundle(.module).cardBackgroundMotion(
                    .float2(size), .float(time), .float(strength), .float(Double(seed % 65_536) / 65_536)
                ),
                maxSampleOffset: CGSize(width: strength * 2 * size.width / 400, height: strength * 2 * size.width / 400)
            )
        } else {
            content
        }
    }
}

public struct AnimatedCardBackground: View {
    private let seed: CardBackgroundSeed
    private let isAnimationEnabled: Bool
    private let resolution: CardBackgroundResolution
    @ObservedObject private var environment = CardBackgroundAnimationEnvironment.shared
    @State private var visible = false
    @State private var startedAt = Date()

    public init(seed: CardBackgroundSeed, isAnimationEnabled: Bool = false, resolution: CardBackgroundResolution = .full) {
        self.seed = seed
        self.isAnimationEnabled = isAnimationEnabled
        self.resolution = resolution
    }

    private var active: Bool {
        guard #available(iOS 17, *) else { return false }
        return CardBackgroundMotionPolicy(
            requested: isAnimationEnabled && resolution == .full,
            animationsEnabled: environment.animationsEnabled, lowPowerMode: environment.lowPowerMode,
            reduceMotion: environment.reduceMotion, applicationActive: environment.applicationActive, visible: visible
        ).canAnimate
    }

    public var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    CardBackgroundMotionFrame(seed: seed,
                        time: max(0, timeline.date.timeIntervalSince(startedAt)) * CardBackgroundMotion.defaultSpeed)
                }
            } else {
                // No timeline, display link, shader, or vector work while static.
                CardBackgroundRaster(seed: seed, resolution: resolution)
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: active) { if $0 { startedAt = Date() } }
        .onChange(of: seed) { _ in startedAt = Date() }
    }
}
