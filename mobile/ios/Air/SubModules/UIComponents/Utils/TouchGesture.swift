
import Foundation
import SwiftUI
import WalletContext

/// FB18199844
///
/// Demo project to showcase a ScrollView bug in iOS 26.
/// Applying a `simultaneousGesture` to a view inside a ScrollView
/// prevents the ScrollView from scrolling as expected.
///
/// Expected behavior: Since we're using .simultaneousGesture, the scroll view
/// should also receive touch and be scrollable.
///
/// To reproduce, please run the project using Xcode 26.0 beta (17A5241e)
/// and simulator running iOS 26 (23A5260I).
///
/// Update: Apple suggested a workaround. Implemented using a SimultaneousLongPressGestureView.

extension View {
    @ViewBuilder
    public func touchGesture(_ binding: Binding<Bool>) -> some View {
        if #available(iOS 18, *) {
            self.gesture(
                TouchGesture(
                    onBegan: { binding.wrappedValue = true },
                    onChanged: { _ in },
                    onEnded: { binding.wrappedValue = false }
                )
            )
        } else {
            self.simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in binding.wrappedValue = true }
                    .onEnded { _ in binding.wrappedValue = false }
            )
        }
    }
}


struct TouchGesture: UIGestureRecognizerRepresentable {
    let onBegan: () -> Void
    let onChanged: (UILongPressGestureRecognizer) -> Void
    let onEnded: () -> Void

    init(onBegan: @escaping () -> Void = {},
         onChanged: @escaping (UILongPressGestureRecognizer) -> Void,
         onEnded: @escaping () -> Void = {}) {
        self.onBegan = onBegan
        self.onChanged = onChanged
        self.onEnded = onEnded
    }
    
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let gestureRecognizer = UILongPressGestureRecognizer()
        gestureRecognizer.minimumPressDuration = 0.0
        gestureRecognizer.allowableMovement = 16.0
        gestureRecognizer.delegate = context.coordinator
        return gestureRecognizer
    }
    
    func handleUIGestureRecognizerAction(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
        switch gestureRecognizer.state {
        case .began:
            onBegan()
            onChanged(gestureRecognizer)
            context.coordinator.gestureStart = gestureRecognizer.location(in: nil)
        case .changed:
            onChanged(gestureRecognizer)
            let position = gestureRecognizer.location(in: nil)
            if let gestureStart = context.coordinator.gestureStart {
                let translation = abs(position.x - gestureStart.x) + abs(position.y - gestureStart.y)
                if translation > 16 {
                    gestureRecognizer.state = .cancelled
                }
            }
        case .ended, .cancelled:
            onEnded()
        default:
            break
        }
    }
    
    func updateUIGestureRecognizer(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        
        var gestureStart: CGPoint?
        
        // Key method for simultaneous recognition with ScrollView
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        // Optional: Add conditions to fail early if needed
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Add any conditions here to fail early if the gesture is invalid
            return true
        }
    }
}
