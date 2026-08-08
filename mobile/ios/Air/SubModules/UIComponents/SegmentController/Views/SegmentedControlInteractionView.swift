import ContextMenuKit
import UIKit
import WalletContext

@MainActor
final class SegmentedControlInteractionView: UIView {

    private var selectionTapGestureRecognizer: UITapGestureRecognizer?
    private var contextMenuInteraction: ContextMenuInteraction?
    private var onSelect: (@MainActor () -> Void)?
    private var currentProvider: SegmentedControlContextMenuProvider?
    private var currentMenuTriggers: ContextMenuInteractionTriggers = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        isSelected: Bool,
        itemId: String,
        title: String,
        contextMenuProvider: SegmentedControlContextMenuProvider?,
        segmentedControl: WSegmentedControl,
        onSelect: @escaping @MainActor () -> Void
    ) {
        self.onSelect = onSelect
        self.accessibilityLabel = title
        self.accessibilityTraits = isSelected ? [.button, .selected] : .button
        self.updateSelectionTap(isSelected: isSelected)
        self.updateContextMenuInteraction(
            isSelected: isSelected,
            itemId: itemId,
            contextMenuProvider: contextMenuProvider,
            segmentedControl: segmentedControl
        )
    }

    override func accessibilityActivate() -> Bool {
        guard let onSelect else { return false }
        onSelect()
        return true
    }

    private func updateSelectionTap(isSelected: Bool) {
        if !isSelected {
            if self.selectionTapGestureRecognizer == nil {
                let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleSelectionTap))
                self.addGestureRecognizer(gestureRecognizer)
                self.selectionTapGestureRecognizer = gestureRecognizer
            }
        } else if let gestureRecognizer = self.selectionTapGestureRecognizer {
            self.removeGestureRecognizer(gestureRecognizer)
            self.selectionTapGestureRecognizer = nil
        }
    }

    private func updateContextMenuInteraction(
        isSelected: Bool,
        itemId: String,
        contextMenuProvider: SegmentedControlContextMenuProvider?,
        segmentedControl: WSegmentedControl
    ) {
        guard let contextMenuProvider else {
            self.contextMenuInteraction?.detach()
            self.contextMenuInteraction = nil
            self.currentProvider = nil
            self.currentMenuTriggers = []
            return
        }

        let menuTriggers: ContextMenuInteractionTriggers = isSelected ? [.tap, .longPress] : [.longPress]
        let needsReattach =
            self.contextMenuInteraction == nil ||
            self.currentProvider !== contextMenuProvider ||
            self.currentMenuTriggers != menuTriggers

        guard needsReattach else { return }

        self.contextMenuInteraction?.detach()

        let interaction = ContextMenuInteraction(
            triggers: menuTriggers,
            sourcePortal: contextMenuProvider.sourcePortal,
            // Keep the activation view's geometry stable while its contents shrink. The same view
            // supplies the context-menu anchor and backdrop cutout, so transforming the view itself
            // would make a long-press menu hug it more tightly than a tap-opened menu.
            pressAnimation: .default(transformMode: .sublayerTransform),
            activationViewProvider: { [weak segmentedControl] _ in
                segmentedControl?.contextMenuActivationView(forItemId: itemId)
            },
            configurationProvider: { _ in
                contextMenuProvider.makeConfiguration()
            }
        )
        interaction.attach(to: self)
        self.contextMenuInteraction = interaction
        self.currentProvider = contextMenuProvider
        self.currentMenuTriggers = menuTriggers
    }

    @objc private func handleSelectionTap() {
        self.onSelect?()
    }
}
