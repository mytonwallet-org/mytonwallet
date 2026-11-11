import ContextMenuKit
import UIKit
import WalletContext

@MainActor
final class SegmentedControlInteractionView: UIView, UIGestureRecognizerDelegate {

    private var selectionTapGestureRecognizer: UITapGestureRecognizer?
    private var contextMenuInteraction: ContextMenuInteraction?
    private var onSelect: (@MainActor () -> Void)?
    private var currentProvider: SegmentedControlContextMenuProvider?
    private var currentMenuTriggers: ContextMenuInteractionTriggers = []
    private var allowsSimultaneousGlassInteraction = false

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
        accessibilityIdentifier: String? = nil,
        contextMenuProvider: SegmentedControlContextMenuProvider?,
        hasControlContextMenu: Bool = false,
        controlContextMenuAccessibilityLabel: String? = nil,
        segmentedControl: WSegmentedControl,
        allowsSimultaneousGlassInteraction: Bool = false,
        onSelect: @escaping @MainActor () -> Void
    ) {
        let shouldOpenControlMenu = isSelected && hasControlContextMenu && contextMenuProvider == nil
        if shouldOpenControlMenu {
            self.onSelect = { [weak segmentedControl] in
                _ = segmentedControl?.presentLongPressContextMenu()
            }
        } else {
            self.onSelect = onSelect
        }
        self.allowsSimultaneousGlassInteraction = allowsSimultaneousGlassInteraction
        self.accessibilityLabel = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityTraits = isSelected ? [.button, .selected] : .button
        if hasControlContextMenu, let controlContextMenuAccessibilityLabel {
            self.accessibilityCustomActions = [UIAccessibilityCustomAction(
                name: controlContextMenuAccessibilityLabel,
                actionHandler: { [weak segmentedControl] _ in
                    segmentedControl?.presentLongPressContextMenu() ?? false
                }
            )]
        } else {
            self.accessibilityCustomActions = nil
        }
        self.updateSelectionTap(isEnabled: !isSelected || shouldOpenControlMenu)
        self.updateContextMenuInteraction(
            isSelected: isSelected,
            itemId: itemId,
            contextMenuProvider: contextMenuProvider,
            hasControlContextMenu: hasControlContextMenu,
            segmentedControl: segmentedControl
        )
    }

    override func accessibilityActivate() -> Bool {
        guard let onSelect else { return false }
        onSelect()
        return true
    }

    private func updateSelectionTap(isEnabled: Bool) {
        if isEnabled {
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

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === selectionTapGestureRecognizer,
              allowsSimultaneousGlassInteraction else {
            return false
        }
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            var view = otherGestureRecognizer.view
            while let candidate = view {
                if let effectView = candidate as? UIVisualEffectView,
                   effectView.effect is UIGlassEffect {
                    return true
                }
                view = candidate.superview
            }
        }
        return false
    }

    private func updateContextMenuInteraction(
        isSelected: Bool,
        itemId: String,
        contextMenuProvider: SegmentedControlContextMenuProvider?,
        hasControlContextMenu: Bool,
        segmentedControl: WSegmentedControl
    ) {
        let menuTriggers: ContextMenuInteractionTriggers = hasControlContextMenu
            ? (isSelected ? [.tap] : [])
            : (isSelected ? [.tap, .longPress] : [.longPress])
        guard let contextMenuProvider, !menuTriggers.isEmpty else {
            self.contextMenuInteraction?.detach()
            self.contextMenuInteraction = nil
            self.currentProvider = nil
            self.currentMenuTriggers = []
            return
        }

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
