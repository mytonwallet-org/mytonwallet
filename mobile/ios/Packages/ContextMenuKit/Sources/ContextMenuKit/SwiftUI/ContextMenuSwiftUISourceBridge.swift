import SwiftUI
import UIKit

@available(iOS 16.0, *)
typealias ContextMenuLongPressSequenceValue = SequenceGesture<LongPressGesture, DragGesture>.Value

@MainActor
@available(iOS 16.0, *)
final class ContextMenuSwiftUISourceBridge: ObservableObject {
    private weak var anchorView: ContextMenuSourceAnchorView?
    private weak var presentedSession: (any ContextMenuPresentationSession)?

    private var isEnabled = true
    private var presentationMode: ContextMenuPresentationMode = .overlay
    private var sourcePortal: ContextMenuSourcePortal?
    private var configuration: (() -> ContextMenuConfiguration?)?
    private var isExternalSelectionActive = false

    func update(
        anchorView: ContextMenuSourceAnchorView,
        isEnabled: Bool,
        presentationMode: ContextMenuPresentationMode,
        sourcePortal: ContextMenuSourcePortal?,
        configuration: @escaping () -> ContextMenuConfiguration?
    ) {
        self.anchorView = anchorView
        self.isEnabled = isEnabled
        self.presentationMode = presentationMode
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
        self.presentMenuIfNeeded(triggeredByLongPress: false)
    }

    func handleLongPressBegan(at point: CGPoint) {
        guard self.isEnabled else {
            return
        }
        self.presentMenuIfNeeded(triggeredByLongPress: true)
        self.presentedSession?.updateExternalSelection(at: point)
    }

    func handleLongPressChanged(at point: CGPoint) {
        guard self.isEnabled else {
            return
        }
        self.presentMenuIfNeeded(triggeredByLongPress: true)
        if !self.isExternalSelectionActive {
            self.presentedSession?.beginExternalSelection(at: point)
            self.isExternalSelectionActive = true
        }
        self.presentedSession?.updateExternalSelection(at: point)
    }

    func handleLongPressEnded(performAction: Bool) {
        guard self.isExternalSelectionActive else {
            return
        }

        self.presentedSession?.endExternalSelection(performAction: performAction)
        self.isExternalSelectionActive = false
    }

    func handleLongPressChanged(_ value: ContextMenuLongPressSequenceValue) {
        guard self.isEnabled else {
            return
        }

        switch value {
        case .first:
            // A touch that may become a hold readies its haptic
            ContextMenuHaptics.prepare()
        case let .second(true, nil):
            self.presentMenuIfNeeded(triggeredByLongPress: true)
        case let .second(true, drag?):
            self.presentMenuIfNeeded(triggeredByLongPress: true)
            guard drag.translation != .zero else {
                return
            }
            if !self.isExternalSelectionActive {
                self.presentedSession?.beginExternalSelection(at: drag.location)
                self.isExternalSelectionActive = true
            }
            self.presentedSession?.updateExternalSelection(at: drag.location)
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

        self.presentedSession?.endExternalSelection(performAction: shouldPerformAction)
        self.isExternalSelectionActive = false
    }

    private func presentMenuIfNeeded(triggeredByLongPress: Bool = false) {
        guard self.presentedSession == nil, let anchorView, let configuration else {
            return
        }
        guard let configuration = configuration() else {
            return
        }
        if triggeredByLongPress {
            ContextMenuHaptics.playLongPressActivation()
        }

        let presentationReference = self.makePresentationReference(for: anchorView)
        guard let session = ContextMenuPresenter.present(
            configuration: configuration,
            from: anchorView,
            presentation: self.presentationMode,
            presentationReference: presentationReference
        ) else {
            return
        }

        session.onDidDismiss = { [weak self, weak session] in
            guard let self else {
                return
            }
            if self.presentedSession === session {
                self.presentedSession = nil
                self.isExternalSelectionActive = false
            }
        }
        self.presentedSession = session
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
