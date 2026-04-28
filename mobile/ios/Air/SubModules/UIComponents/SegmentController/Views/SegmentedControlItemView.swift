import ContextMenuKit
import Perception
import SwiftUI
import UIKit
import WalletContext

struct SegmentedControlItemView: View {
    let model: SegmentedControlModel
    var item: SegmentedControlItem

    var body: some View {
        WithPerceptionTracking {
            _SegmentedControlItemView(
                selectedItemId: model.selection?.effectiveSelectedItemID,
                distanceToItem: model.distanceToItem(itemId: item.id),
                item: item,
                innerPadding: model.constants.innerPadding,
                itemHeight: model.constants.height,
                accessoryWidth: model.constants.accessoryWidth,
                onSelect: {
                    model.onSelect(item)
                }
            )
        }
    }
}

struct _SegmentedControlItemView: View {
    var selectedItemId: String?
    var distanceToItem: CGFloat
    var item: SegmentedControlItem
    var innerPadding: CGFloat
    var itemHeight: CGFloat
    var accessoryWidth: CGFloat
    var onSelect: @MainActor () -> Void

    var isSelected: Bool { selectedItemId == item.id }

    var body: some View {
        content
            .fixedSize()
            .padding(.horizontal, innerPadding)
            .frame(height: itemHeight)
            .contentShape(.capsule)
            .overlay {
                SegmentedControlInteractionAttachmentView(
                    isSelected: isSelected,
                    contextMenuProvider: item.contextMenuProvider,
                    onSelect: onSelect
                )
            }
    }

    var content: some View {
        HStack(spacing: 0) {
            Text(item.title)
            if item.shouldShowMenuIconWhenActive {
                _SegmentedControlItemAccessory(distanceToItem: distanceToItem, accessoryWidth: accessoryWidth)
            }
        }
    }
}

private struct SegmentedControlInteractionAttachmentView: UIViewRepresentable {
    let isSelected: Bool
    let contextMenuProvider: SegmentedControlContextMenuProvider?
    let onSelect: @MainActor () -> Void

    func makeUIView(context: Context) -> SegmentedControlInteractionView {
        let view = SegmentedControlInteractionView()
        view.update(
            isSelected: self.isSelected,
            contextMenuProvider: self.contextMenuProvider,
            onSelect: self.onSelect
        )
        return view
    }

    func updateUIView(_ uiView: SegmentedControlInteractionView, context: Context) {
        uiView.update(
            isSelected: self.isSelected,
            contextMenuProvider: self.contextMenuProvider,
            onSelect: self.onSelect
        )
    }
}

@MainActor
private final class SegmentedControlInteractionView: UIView, UIGestureRecognizerDelegate {
    private var selectionTapGestureRecognizer: UITapGestureRecognizer?
    private var contextMenuInteraction: ContextMenuInteraction?
    private var onSelect: (@MainActor () -> Void)?
    private weak var currentSourceView: UIView?
    private var currentProvider: SegmentedControlContextMenuProvider?
    private var currentMenuTriggers: ContextMenuInteractionTriggers = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        isSelected: Bool,
        contextMenuProvider: SegmentedControlContextMenuProvider?,
        onSelect: @escaping @MainActor () -> Void
    ) {
        self.onSelect = onSelect
        self.updateSelectionTap(isSelected: isSelected)
        self.updateContextMenuInteraction(
            isSelected: isSelected,
            contextMenuProvider: contextMenuProvider
        )
    }

    private func updateSelectionTap(isSelected: Bool) {
        if !isSelected {
            if self.selectionTapGestureRecognizer == nil {
                let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleSelectionTap))
                gestureRecognizer.delegate = self
                self.addGestureRecognizer(gestureRecognizer)
                self.selectionTapGestureRecognizer = gestureRecognizer
            }
        } else if let gestureRecognizer = self.selectionTapGestureRecognizer {
            self.removeGestureRecognizer(gestureRecognizer)
            self.selectionTapGestureRecognizer = nil
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === selectionTapGestureRecognizer && otherGestureRecognizer is UILongPressGestureRecognizer
    }

    private func updateContextMenuInteraction(
        isSelected: Bool,
        contextMenuProvider: SegmentedControlContextMenuProvider?
    ) {
        guard let contextMenuProvider else {
            self.contextMenuInteraction?.detach()
            self.contextMenuInteraction = nil
            self.currentSourceView = nil
            self.currentProvider = nil
            self.currentMenuTriggers = []
            return
        }

        let menuTriggers: ContextMenuInteractionTriggers = isSelected ? [.tap, .longPress] : [.longPress]
        let needsReattach =
            self.contextMenuInteraction == nil ||
            self.currentProvider !== contextMenuProvider ||
            self.currentMenuTriggers != menuTriggers ||
            self.currentSourceView !== self

        guard needsReattach else {
            return
        }

        self.contextMenuInteraction?.detach()

        let interaction = ContextMenuInteraction(
            triggers: menuTriggers,
            sourcePortal: contextMenuProvider.sourcePortal
        ) { _ in
            contextMenuProvider.makeConfiguration()
        }
        interaction.attach(to: self)
        self.contextMenuInteraction = interaction
        self.currentSourceView = self
        self.currentProvider = contextMenuProvider
        self.currentMenuTriggers = menuTriggers
    }

    @objc private func handleSelectionTap() {
        self.onSelect?()
    }
}

struct _SegmentedControlItemAccessory: View {
    var distanceToItem: CGFloat
    var accessoryWidth: CGFloat

    var body: some View {
        Image.airBundle("SegmentedControlArrow")
            .opacity(0.5)
            .offset(x: 4)
            .scaleEffect(1 - distanceToItem)
            .frame(width: accessoryWidth * (1 - distanceToItem), alignment: .leading)
    }
}
