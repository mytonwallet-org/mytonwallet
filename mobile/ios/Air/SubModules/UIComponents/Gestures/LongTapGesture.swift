
import UIKit
import SwiftUI


extension View {
    @ViewBuilder
    public func longTapGesture_ios18(
        isEnabled: Bool,
        onLongTap: @escaping () -> (),
    ) -> some View {
        if #available(iOS 18, *) {
            self.gesture(
                CustomLongTapGesture(isEnabled: isEnabled, onLongTap: onLongTap)
            )
        } else {
            self
        }
    }
}

@available(iOS 18, *)
struct CustomLongTapGesture: UIGestureRecognizerRepresentable {
    
    var isEnabled: Bool
    var onLongTap: () -> ()

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 0.25
        g.allowableMovement = 10
        return g
    }
    
    func updateUIGestureRecognizer(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
        gestureRecognizer.isEnabled = isEnabled
    }
    
    func handleUIGestureRecognizerAction(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
        switch gestureRecognizer.state {
        case .began:
            onLongTap()
        default:
            break
        }
    }
}
