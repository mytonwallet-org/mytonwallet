import Perception
import SwiftUI
import WalletCore

public struct LoadingShineMask: View {
    private let isActive: Bool

    public init(isActive: Bool) {
        self.isActive = isActive
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date.now

    public var body: some View {
        WithPerceptionTracking {
            if isActive && AppStorageHelper.animations && !reduceMotion {
                TimelineView(.animation) { timeline in
                    // Match the skeleton's one-second sweep followed by a one-second pause.
                    let elapsed = max(0, timeline.date.timeIntervalSince(animationStart)).truncatingRemainder(dividingBy: 2)
                    let sweep = min(elapsed, 1) * 1.6
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: -0.6 + sweep),
                            .init(color: .white.opacity(0.35), location: -0.3 + sweep),
                            .init(color: .white, location: sweep),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            } else {
                Rectangle().fill(.white)
            }
        }
        .onChange(of: isActive) { isActive in
            if isActive {
                animationStart = .now
            }
        }
    }
}
