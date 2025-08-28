//
//  File.swift
//  Dragula
//
//  Created by Mustafa Yusuf on 06/06/25.
//

#if !os(watchOS)
import SwiftUI
import UIKit

/// A SwiftUI-compatible wrapper for a `UIView` that supports UIDragInteraction.
///
/// Allows injecting drag preview and drop views with drag lifecycle callbacks.
///
/// - Parameters:
///   - Preview: The view used as the visual representation during drag.
///   - DropView: The view displayed when the item is being dragged.
///   - itemProvider: Provides the data for the drag session.
///   - onDragWillBegin: Called when a drag is about to begin.
///   - onDragWillEnd: Called when the drag session ends.
struct DraggableView<Preview: View, DropView: View>: UIViewRepresentable {
    
    @Environment(\.dragPreviewCornerRadius) private var dragPreviewCornerRadius
    
    private let itemProvider: () -> NSItemProvider
    private let onDragWillBegin: (() -> Void)?
    private let onDragWillEnd: (() -> Void)?
    private let preview: () -> Preview
    private let dropView: () -> DropView

    /// Initializes a draggable view.
    /// - Parameters:
    ///   - preview: The drag preview view.
    ///   - dropView: The drop indicator view.
    ///   - itemProvider: Closure to provide the drag item.
    ///   - onDragWillBegin: Called before drag starts.
    ///   - onDragWillEnd: Called when drag ends.
    init(
        @ViewBuilder preview: @escaping () -> Preview,
        @ViewBuilder dropView: @escaping () -> DropView,
        itemProvider: @escaping () -> NSItemProvider,
        onDragWillBegin: (() -> Void)?,
        onDragWillEnd: (() -> Void)?
    ) {
        self.preview = preview
        self.dropView = dropView
        self.itemProvider = itemProvider
        self.onDragWillBegin = onDragWillBegin
        self.onDragWillEnd = onDragWillEnd
    }

    func makeUIView(context: Context) -> DraggableUIView {
        let uiPreview = UIHostingController(rootView: preview()).view!
        uiPreview.backgroundColor = .clear
        let uiDropView = UIHostingController(rootView: dropView()).view!
        uiDropView.backgroundColor = .clear

        let draggableView = DraggableUIView(
            preview: uiPreview,
            dropView: uiDropView,
            itemProvider: itemProvider,
            onDragWillBegin: onDragWillBegin,
            onDragWillEnd: onDragWillEnd
        )
        draggableView.dragPreviewCornerRadius = dragPreviewCornerRadius
        return draggableView
    }

    func updateUIView(_ uiView: DraggableUIView, context: Context) {
        uiView.dragPreviewCornerRadius = dragPreviewCornerRadius
    }
}

extension DraggableView {
    final class DraggableUIView: UIView, UIDragInteractionDelegate {
        var dragPreviewCornerRadius: CGFloat = .zero
        private let previewView: UIView
        private let dropIndicatorView: UIView
        private let itemProvider: () -> NSItemProvider
        private let onDragWillBegin: (() -> Void)?
        private let onDragWillEnd: (() -> Void)?
        
    
        init(
            preview: UIView,
            dropView: UIView,
            itemProvider: @escaping () -> NSItemProvider,
            onDragWillBegin: (() -> Void)? = nil,
            onDragWillEnd: (() -> Void)? = nil
        ) {
            self.previewView = preview
            self.dropIndicatorView = dropView
            self.itemProvider = itemProvider
            self.onDragWillBegin = onDragWillBegin
            self.onDragWillEnd = onDragWillEnd
            
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = true
            let dragInteraction = UIDragInteraction(delegate: self)
            previewView.addInteraction(dragInteraction)
            
            self.addSubview(previewView)
            self.addSubview(dropIndicatorView)
            self.dropIndicatorView.alpha = .zero
            self.previewView.translatesAutoresizingMaskIntoConstraints = false
            self.dropIndicatorView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                self.previewView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                self.previewView.topAnchor.constraint(equalTo: self.topAnchor),
                self.previewView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                self.previewView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                
                self.dropIndicatorView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                self.dropIndicatorView.topAnchor.constraint(equalTo: self.topAnchor),
                self.dropIndicatorView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                self.dropIndicatorView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            ])
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            itemsForBeginning session: UIDragSession
        ) -> [UIDragItem] {
            onDragWillBegin?()
            let itemProvider = self.itemProvider()
            return [UIDragItem(itemProvider: itemProvider)]
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            itemsForAddingTo session: any UIDragSession,
            withTouchAt point: CGPoint
        ) -> [UIDragItem] {
            onDragWillBegin?()
            let itemProvider = self.itemProvider()
            return [UIDragItem(itemProvider: itemProvider)]
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            previewForLifting item: UIDragItem,
            session: UIDragSession
        ) -> UITargetedDragPreview? {
            guard let sourceView = interaction.view else {
                return nil
            }
            
            let previewView = UIImageView(image: sourceView.snapshot())
            previewView.bounds = sourceView.bounds
            
            let parameters = UIDragPreviewParameters()
            parameters.visiblePath = UIBezierPath(
                roundedRect: previewView.bounds,
                cornerRadius: dragPreviewCornerRadius
            )
            
            let target = UIDragPreviewTarget(container: sourceView.superview!, center: sourceView.center)
            
            return UITargetedDragPreview(view: previewView, parameters: parameters, target: target)
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            willAnimateLiftWith animator: any UIDragAnimating,
            session: any UIDragSession
        ) {
            self.dropIndicatorView.isHidden = false
            
            animator.addAnimations { [weak self] in
                self?.previewView.alpha = .zero
                self?.dropIndicatorView.alpha = 1
            }
            animator.addCompletion { [weak self] test in
                self?.previewView.isHidden = true
            }
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            previewForCancelling item: UIDragItem,
            withDefault defaultPreview: UITargetedDragPreview
        ) -> UITargetedDragPreview? {
            
            guard let view = interaction.view,
                  let superview = view.superview else {
                return defaultPreview
            }
            
            let target = UIDragPreviewTarget(container: superview, center: view.center)
            
            return UITargetedDragPreview(
                view: defaultPreview.view,
                parameters: UIDragPreviewParameters(),
                target: target
            )
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            prefersFullSizePreviewsFor session: any UIDragSession
        ) -> Bool {
            true
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            item: UIDragItem,
            willAnimateCancelWith animator: UIDragAnimating
        ) {
            animator.addAnimations { [weak self] in
                self?.dropIndicatorView.alpha = .zero
                self?.previewView.alpha = 1
            }
            
            animator.addCompletion { [weak self] position in
                self?.previewView.isHidden = false
                self?.dropIndicatorView.isHidden = true
            }
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            session: UIDragSession,
            willEndWith operation: UIDropOperation
        ) {
            onDragWillEnd?()
        }
        
        func dragInteraction(
            _ interaction: UIDragInteraction,
            sessionIsRestrictedToDraggingApplication session: any UIDragSession
        ) -> Bool {
            true
        }
    }
}

fileprivate extension UIView {
    func snapshot() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { context in
            layer.render(in: context.cgContext)
        }
    }
}
#endif
