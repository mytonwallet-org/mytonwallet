import SwiftUI
import UIKit

@available(iOS 16.0, *)
typealias ContextMenuLongPressSequenceValue = SequenceGesture<LongPressGesture, DragGesture>.Value

@MainActor
@available(iOS 16.0, *)
final class ContextMenuSwiftUISourceBridge: ObservableObject {
    private weak var anchorView: ContextMenuSourceAnchorView?
    private var presentedOverlayView: ContextMenuOverlayView?

    private var isEnabled = true
    private var sourcePortal: ContextMenuSourcePortal?
    private var configuration: (() -> ContextMenuConfiguration)?
    private var isExternalSelectionActive = false

    func update(
        anchorView: ContextMenuSourceAnchorView,
        isEnabled: Bool,
        sourcePortal: ContextMenuSourcePortal?,
        configuration: @escaping () -> ContextMenuConfiguration
    ) {
        self.anchorView = anchorView
        self.isEnabled = isEnabled
        self.sourcePortal = sourcePortal
        self.configuration = configuration
    }

    func refreshHierarchy(for anchorView: ContextMenuSourceAnchorView) {
        guard self.anchorView === anchorView else {
            return
        }
        self.anchorView = anchorView
    }

    func detach(anchorView: ContextMenuSourceAnchorView) {
        guard self.anchorView === anchorView else {
            return
        }
        self.anchorView = nil
    }

    func handleTap() {
        guard self.isEnabled else {
            return
        }
        self.presentMenuIfNeeded()
    }

    func handleLongPressBegan(at point: CGPoint) {
        guard self.isEnabled else {
            return
        }
        self.presentMenuIfNeeded()
        self.presentedOverlayView?.updateExternalSelection(at: point)
    }

    func handleLongPressChanged(at point: CGPoint) {
        guard self.isEnabled else {
            return
        }
        self.presentMenuIfNeeded()
        if !self.isExternalSelectionActive {
            self.presentedOverlayView?.beginExternalSelection(at: point)
            self.isExternalSelectionActive = true
        }
        self.presentedOverlayView?.updateExternalSelection(at: point)
    }

    func handleLongPressEnded(performAction: Bool) {
        guard self.isExternalSelectionActive else {
            return
        }

        self.presentedOverlayView?.endExternalSelection(performAction: performAction)
        self.isExternalSelectionActive = false
    }

    func handleLongPressChanged(_ value: ContextMenuLongPressSequenceValue) {
        guard self.isEnabled else {
            return
        }

        switch value {
        case .first(true):
            self.presentMenuIfNeeded()
        case let .second(true, drag?):
            self.presentMenuIfNeeded()
            guard drag.translation != .zero else {
                return
            }
            if !self.isExternalSelectionActive {
                self.presentedOverlayView?.beginExternalSelection(at: drag.location)
                self.isExternalSelectionActive = true
            }
            self.presentedOverlayView?.updateExternalSelection(at: drag.location)
        default:
            break
        }
    }

    func handleLongPressEnded(_ value: ContextMenuLongPressSequenceValue) {
        guard self.isExternalSelectionActive else {
            return
        }

        let shouldPerformAction: Bool
        switch value {
        case .second(true, _):
            shouldPerformAction = true
        default:
            shouldPerformAction = false
        }

        self.presentedOverlayView?.endExternalSelection(performAction: shouldPerformAction)
        self.isExternalSelectionActive = false
    }

    private func presentMenuIfNeeded() {
        guard self.presentedOverlayView == nil, let anchorView, let configuration else {
            return
        }

        let presentationReference = self.makePresentationReference(for: anchorView)
        guard let overlayView = ContextMenuPresenter.present(
            configuration: configuration(),
            from: anchorView,
            presentationReference: presentationReference
        ) else {
            return
        }

        overlayView.onDidDismiss = { [weak self, weak overlayView] in
            guard let self else {
                return
            }
            if self.presentedOverlayView === overlayView {
                self.presentedOverlayView = nil
                self.isExternalSelectionActive = false
            }
        }
        self.presentedOverlayView = overlayView
    }

    private func makePresentationReference(for anchorView: UIView) -> ContextMenuPresentationReference {
        ContextMenuPresentationReference.from(view: anchorView, sourcePortal: self.sourcePortal)
    }
}

@MainActor
@available(iOS 16.0, *)
final class ContextMenuSourceAnchorView: UIView {
    weak var bridge: ContextMenuSwiftUISourceBridge?
    var onHierarchyDidChange: ((ContextMenuSourceAnchorView) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        self.onHierarchyDidChange?(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.onHierarchyDidChange?(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.onHierarchyDidChange?(self)
    }
}
