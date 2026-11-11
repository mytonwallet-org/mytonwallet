import UIKit

@MainActor
enum ContextMenuHaptics {
    private static let transitionGenerator = UIImpactFeedbackGenerator(style: .soft)

    /// Wakes the haptic engine ahead of an impact: one played as the generator is made, or after a while without
    /// impacts, can be dropped, as the first hold's was
    static func prepare() {
        transitionGenerator.prepare()
    }

    static func playLongPressActivation() {
        transitionGenerator.impactOccurred(intensity: 0.75)
    }

    static func playRowLift() {
        transitionGenerator.impactOccurred(intensity: 1.0)
    }
}
