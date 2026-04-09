import SwiftUI
import UIKit

@available(iOS 16.0, *)
public extension View {
    func contextMenuSource(
        isEnabled: Bool = true,
        triggers: ContextMenuInteractionTriggers = [.tap, .longPress],
        sourcePortal: ContextMenuSourcePortal? = nil,
        configuration: @escaping () -> ContextMenuConfiguration
    ) -> some View {
        self.modifier(
            ContextMenuSourceModifier(
                isEnabled: isEnabled,
                triggers: triggers,
                sourcePortal: sourcePortal,
                configuration: configuration
            )
        )
    }
}

@available(iOS 16.0, *)
private struct ContextMenuSourceModifier: ViewModifier {
    let isEnabled: Bool
    let triggers: ContextMenuInteractionTriggers
    let sourcePortal: ContextMenuSourcePortal?
    let configuration: () -> ContextMenuConfiguration

    @StateObject private var bridge = ContextMenuSwiftUISourceBridge()

    func body(content: Content) -> some View {
        let base = content
            .contentShape(Rectangle())
            .background(
                ContextMenuSourceAttachmentView(
                    bridge: self.bridge,
                    isEnabled: self.isEnabled,
                    sourcePortal: self.sourcePortal,
                    configuration: self.configuration
                )
            )
            .gesture(self.tapGesture, isEnabled: self.triggers.contains(.tap))

        if #available(iOS 18.0, *) {
            let bridge = self.bridge
            if self.triggers.contains(.longPress) {
                base.gesture(
                    ContextMenuHoldAndDragGesture(
                        onBegan: { point in
                            bridge.handleLongPressBegan(at: point)
                        },
                        onChanged: { point in
                            bridge.handleLongPressChanged(at: point)
                        },
                        onEnded: { performAction in
                            bridge.handleLongPressEnded(performAction: performAction)
                        }
                    )
                )
            } else {
                base
            }
        } else {
            base.gesture(self.fallbackLongPressGesture, isEnabled: self.triggers.contains(.longPress))
        }
    }

    private var tapGesture: some Gesture {
        let bridge = self.bridge
        return TapGesture().onEnded {
            bridge.handleTap()
        }
    }

    private var fallbackLongPressGesture: some Gesture {
        let bridge = self.bridge
        return LongPressGesture(minimumDuration: 0.32, maximumDistance: 16.0)
            .sequenced(before: DragGesture(minimumDistance: 0.0, coordinateSpace: .global))
            .onChanged { value in
                bridge.handleLongPressChanged(value)
            }
            .onEnded { value in
                bridge.handleLongPressEnded(value)
            }
    }
}

@available(iOS 18.0, *)
private struct ContextMenuHoldAndDragGesture: UIGestureRecognizerRepresentable {
    typealias UIGestureRecognizerType = UILongPressGestureRecognizer

    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let gestureRecognizer = UILongPressGestureRecognizer()
        gestureRecognizer.minimumPressDuration = 0.25
        gestureRecognizer.allowableMovement = 10.0
        return gestureRecognizer
    }

    func updateUIGestureRecognizer(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
    }

    func handleUIGestureRecognizerAction(_ gestureRecognizer: UILongPressGestureRecognizer, context: Context) {
        switch gestureRecognizer.state {
        case .began:
            let point = gestureRecognizer.location(in: nil)
            self.onBegan(point)
        case .changed:
            let point = gestureRecognizer.location(in: nil)
            self.onChanged(point)
        case .ended:
            self.onEnded(true)
        case .cancelled, .failed:
            self.onEnded(false)
        default:
            break
        }
    }
}

@available(iOS 16.0, *)
private struct ContextMenuSourceAttachmentView: UIViewRepresentable {
    @ObservedObject var bridge: ContextMenuSwiftUISourceBridge
    let isEnabled: Bool
    let sourcePortal: ContextMenuSourcePortal?
    let configuration: () -> ContextMenuConfiguration

    func makeUIView(context: Context) -> ContextMenuSourceAnchorView {
        let view = ContextMenuSourceAnchorView()
        view.bridge = self.bridge
        view.onHierarchyDidChange = { [weak bridge = self.bridge] anchorView in
            bridge?.refreshHierarchy(for: anchorView)
        }
        return view
    }

    func updateUIView(_ uiView: ContextMenuSourceAnchorView, context: Context) {
        self.bridge.update(
            anchorView: uiView,
            isEnabled: self.isEnabled,
            sourcePortal: self.sourcePortal,
            configuration: self.configuration
        )
    }

    static func dismantleUIView(_ uiView: ContextMenuSourceAnchorView, coordinator: ()) {
        let bridge = uiView.bridge
        uiView.onHierarchyDidChange = nil
        uiView.bridge = nil
        Task { @MainActor in
            bridge?.detach(anchorView: uiView)
        }
    }
}
