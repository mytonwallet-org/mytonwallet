import UIKit

@MainActor
enum ContextMenuHaptics {
    private static let transitionGenerator = UIImpactFeedbackGenerator(style: .soft)

    static func playLongPressActivation() {
        transitionGenerator.impactOccurred(intensity: 0.75)
    }
}
