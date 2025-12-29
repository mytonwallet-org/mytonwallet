
import UIKit
import SwiftUI

extension View {
    @ViewBuilder
    public func tapGesture(
        onTap: @escaping () -> (),
    ) -> some View {
        if #available(iOS 18, *) {
            self.gesture(
                _TapGesture(onTap: onTap)
            )
        } else {
            self.simultaneousGesture(
                TapGesture()
                    .onEnded(onTap)
            )
        }
    }
}

@available(iOS 18, *)
struct _TapGesture: UIGestureRecognizerRepresentable {
    
    var onTap: () -> ()
    
    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let g = UITapGestureRecognizer()
        return g
    }
    
    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
    }
    
    func handleUIGestureRecognizerAction(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
        switch gestureRecognizer.state {
        case .ended:
            onTap()
        default:
            break
        }
    }
}
