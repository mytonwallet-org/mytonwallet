import ContextMenuKit
import SwiftUI
import UIKit
import WalletContext

/// The transaction receipt toolbar, shared by activity details and trading receipts.
public struct ReceiptActionsView: View {
    private let model: ReceiptActionsToolbar.Model

    public init(onDetails: (() -> Void)? = nil, onRepeat: (() -> Void)? = nil,
                onShare: (() -> Void)? = nil, onWearMenu: (() -> ContextMenuConfiguration?)? = nil,
                detailsExpanded: Bool = false, accessibilityPrefix: String = "activityDetails",
                shareIconName: String = "ShareIconBold") {
        model = .init(showWear: onWearMenu != nil, showDetails: onDetails != nil,
                      showRepeat: onRepeat != nil, showShare: onShare != nil,
                      onWearMenu: onWearMenu ?? { nil }, onDetailsExpanded: onDetails ?? {},
                      onRepeat: onRepeat ?? {}, onShare: onShare ?? {},
                      accessibilityPrefix: accessibilityPrefix, detailsExpanded: detailsExpanded, shareIconName: shareIconName)
    }

    public var body: some View {
        GeometryReader { proxy in
            ReceiptActionsToolbarRepresentable(model: model)
                .id(model.shareIconName)
                .frame(width: model.width(constrainedTo: proxy.size.width), height: WScalableButton.preferredHeight)
                .frame(width: proxy.size.width, height: WScalableButton.preferredHeight, alignment: .center)
        }
        .frame(height: WScalableButton.preferredHeight)
        .tint(.accentColor)
    }
}

private final class ReceiptActionsToolbar: ButtonsToolbar {
    var wearButton: WScalableButton!
    var detailsButton: WScalableButton!
    var repeatButton: WScalableButton!
    var shareButton: WScalableButton!
    private var model: Model!
    private var wearMenuInteraction: ContextMenuInteraction?

    struct Model {
        let showWear: Bool
        let showDetails: Bool
        let showRepeat: Bool
        let showShare: Bool
        let onWearMenu: () -> ContextMenuConfiguration?
        let onDetailsExpanded: () -> Void
        let onRepeat: () -> Void
        let onShare: () -> Void
        let accessibilityPrefix: String
        let detailsExpanded: Bool
        let shareIconName: String

        @MainActor var visibleCount: Int {
            [showWear, showDetails, showRepeat, showShare].filter { $0 }.count
        }

        @MainActor func width(constrainedTo availableWidth: CGFloat) -> CGFloat {
            guard visibleCount > 0 else { return 0 }
            let count = CGFloat(visibleCount)
            let spacing = CGFloat(visibleCount - 1) * ButtonsToolbar.preferredSpacing
            let preferredWidth = count * ButtonsToolbar.preferredItemWidth + spacing
            return min(availableWidth, preferredWidth)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(model: Model) {
        self.model = model
        if detailsButton == nil {
            setupButtons()
        }
        wearButton.isHidden = !model.showWear
        detailsButton.isHidden = !model.showDetails
        repeatButton.isHidden = !model.showRepeat
        shareButton.isHidden = !model.showShare
        detailsButton.accessibilityIdentifier = model.accessibilityPrefix + ".details"
        repeatButton.accessibilityIdentifier = model.accessibilityPrefix + ".repeat"
        shareButton.accessibilityIdentifier = model.accessibilityPrefix + ".share"
        if model.detailsExpanded { detailsButton.accessibilityTraits.insert(.selected) }
        else { detailsButton.accessibilityTraits.remove(.selected) }
        update()
    }

    private func setupButtons() {
        let wear = WScalableButton(title: lang("Wear"), image: UIImage.airBundle("WearIconBold"), onTap: {})
        let interaction = ContextMenuInteraction(
            triggers: [.tap, .longPress],
            longPressDuration: 0.25,
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(
                    cornerRadius: WScalableButton.preferredCornerRadius,
                    cornerCurve: .continuous
                )
            )
        ) { [weak self] _ in
            guard var configuration = self?.model?.onWearMenu() else { return nil }
            configuration.style.glassTint = .subtle
            return configuration
        }
        interaction.attach(to: wear)
        wearMenuInteraction = interaction
        addArrangedSubview(wear)
        wearButton = wear

        let details = WScalableButton(title: lang("Details"), image: UIImage.airBundle("DetailsIconBold"), onTap: { [weak self] in self?.model?.onDetailsExpanded() })
        addArrangedSubview(details)
        detailsButton = details

        let repeatBtn = WScalableButton(title: lang("Repeat"), image: UIImage.airBundle("RepeatIconBold"), onTap: { [weak self] in self?.model?.onRepeat() })
        addArrangedSubview(repeatBtn)
        repeatButton = repeatBtn

        let share = WScalableButton(title: lang("Share"), image: UIImage.airBundle(model.shareIconName), onTap: { [weak self] in  self?.model?.onShare() })
        addArrangedSubview(share)
        shareButton = share
    }
}

private struct ReceiptActionsToolbarRepresentable: UIViewRepresentable {
    var model: ReceiptActionsToolbar.Model

    func makeCoordinator() -> ReceiptActionsToolbar {
        ReceiptActionsToolbar()
    }

    func makeUIView(context: Context) -> UIView {
        let toolbar = context.coordinator
        toolbar.configure(model: model)
        if #available(iOS 26, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = toolbar.spacing
            let glassContainerView = UIVisualEffectView(effect: effect)
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            glassContainerView.contentView.addSubview(toolbar)
            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(equalTo: glassContainerView.contentView.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: glassContainerView.contentView.trailingAnchor),
                toolbar.topAnchor.constraint(equalTo: glassContainerView.contentView.topAnchor),
                toolbar.bottomAnchor.constraint(equalTo: glassContainerView.contentView.bottomAnchor),
            ])
            return glassContainerView
        }
        return toolbar
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.configure(model: model)
    }
}
