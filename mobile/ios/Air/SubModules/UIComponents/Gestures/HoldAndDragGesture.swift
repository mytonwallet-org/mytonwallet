
import UIKit
import SwiftUI


extension View {
    @ViewBuilder
    public func holdAndDragGesture(
        isEnabled: Bool,
        onBegan: @escaping (CGPoint) -> (),
        onChanged: @escaping (CGPoint) -> (),
        onEnded: @escaping () -> (),
    ) -> some View {
        if #available(iOS 18, *) {
            self.gesture(
                HoldAndDragGesture(isEnabled: isEnabled, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
            )
        } else {
            self.gesture(
                LongPressGesture(minimumDuration: 0.25, maximumDistance: 10)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { v in
                        switch v {
                        case .first:
                            break
                        case .second(_, let drag):
                            if let location = drag?.location {
                                onBegan(location)
                                onChanged(location)
                            }
                        }
                    }
                    .onEnded { v in
                        switch v {
                        case .first(_):
                            break
                        case .second(_, _):
                            onEnded()
                        }
                    },
                isEnabled: isEnabled
            )
        }
    }
}

@available(iOS 18, *)
struct HoldAndDragGesture: UIGestureRecognizerRepresentable {
    
    typealias UIGestureRecognizerType = UILongPressGestureRecognizer
    
    var isEnabled: Bool
    var onBegan: (CGPoint) -> ()
    var onChanged: (CGPoint) -> ()
    var onEnded: () -> ()
    
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
            let point = gestureRecognizer.location(in: nil)
            onBegan(point)
            onChanged(point)
        case .changed:
            let point = gestureRecognizer.location(in: nil)
            onChanged(point)
        case .ended, .cancelled:
            onEnded()
        default:
            break
        }
    }
}
