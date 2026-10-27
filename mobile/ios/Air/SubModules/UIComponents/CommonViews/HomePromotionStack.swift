import Dependencies
import Perception
import SwiftUI
import WalletContext
import WalletCore

/// The caller owns ordering, dismissal, and navigation. Only the first banner is interactive.
public struct HomePromotionStack: View {
    public var promotions: [ApiPromotion]
    public var animation: Animation?
    public var transition: AnyTransition
    public var loadingActionId: String?
    public var onAction: (ApiPromotion) -> Void
    public var onDismiss: (ApiPromotion) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Dependency(\.sensitiveData.isHidden) private var isSensitiveDataHidden

    public static var dismissalTransition: AnyTransition {
        .modifier(
            active: PromotionDismissModifier(progress: 1),
            identity: PromotionDismissModifier(progress: 0)
        )
    }

    public static var defaultTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)),
            removal: dismissalTransition
        )
    }

    public init(
        promotions: [ApiPromotion],
        animation: Animation? = .spring(response: 0.4, dampingFraction: 0.85),
        transition: AnyTransition = HomePromotionStack.defaultTransition,
        loadingActionId: String? = nil,
        onAction: @escaping (ApiPromotion) -> Void,
        onDismiss: @escaping (ApiPromotion) -> Void
    ) {
        self.loadingActionId = loadingActionId
        self.promotions = promotions
        self.animation = animation
        self.transition = transition
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        WithPerceptionTracking {
            let isSensitiveDataHidden = self.isSensitiveDataHidden
            let banners = promotions.filter { $0.infoBanner != nil && $0.kind != .cardOverlay }
            let hasNextBanner = banners.count > 1
            ZStack(alignment: .top) {
                if let promotion = banners.first, let banner = promotion.infoBanner {
                    // Reserve the front card's natural height without letting hidden cards affect it.
                    HomePromotionBanner(
                        banner: banner,
                        isSensitiveDataHidden: isSensitiveDataHidden,
                        onAction: {},
                        onDismiss: {}
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        // Keep the hidden third card mounted so it can advance from its own position.
                        ForEach(Array(banners.prefix(3).enumerated()), id: \.element.id) { index, promotion in
                            if let banner = promotion.infoBanner {
                                HomePromotionBanner(
                                    banner: banner,
                                    isSensitiveDataHidden: isSensitiveDataHidden,
                                    showsContent: index == 0,
                                    isLoading: promotion.id == loadingActionId,
                                    onAction: { onAction(promotion) },
                                    onDismiss: { onDismiss(promotion) }
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .scaleEffect(
                                    x: max(0, 1 - CGFloat(index) * 48 / max(geometry.size.width, 1)),
                                    y: 1,
                                    anchor: .bottom
                                )
                                .offset(y: CGFloat(index) * 8)
                                .opacity(index < 2 ? 1 : 0)
                                // This order stays stable as cards advance, keeping the departing card on top.
                                .zIndex(Double(banners.count - index))
                                .allowsHitTesting(index == 0)
                                .accessibilityHidden(index != 0)
                                .transition(reduceMotion ? .opacity : transition)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
            }
            .padding(.bottom, hasNextBanner ? 8 : 0)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : animation, value: banners.map(\.id))
        }
    }
}

private struct PromotionDismissModifier: AnimatableModifier {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let progress = min(max(progress, 0), 1)
        content
            .compositingGroup()
            .blur(radius: 8 * progress)
            .offset(y: -12 * progress)
            .opacity(1 - progress)
    }
}

private struct HomePromotionBanner: View {
    let banner: ApiPromotion.InfoBanner
    let isSensitiveDataHidden: Bool
    var showsContent = true
    var isLoading = false
    let onAction: () -> Void
    let onDismiss: () -> Void

    @State private var isPressed = false
    @State private var isHovering = false
    @State private var isActionHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func localized(_ text: String) -> String {
        banner.localized(text, isSensitiveDataHidden: isSensitiveDataHidden)
    }

    private var description: AttributedString {
        var text = (try? AttributedString(
            markdown: localized(banner.description),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(localized(banner.description))
        for run in text.runs {
            // Banner navigation belongs to the whole card, including emphasized text.
            text[run.range].link = nil
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                text[run.range].font = WTypography.font(.supportingStrong, scaling: .dynamic)
            }
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: localized(banner.title))
                .textStyle(.calloutEmphasized, scaling: .dynamic)
                .tracking(-0.43)
                .foregroundStyle(Color.air.primaryLabel)
                .frame(minHeight: 22, alignment: .leading)
                .padding(.trailing, 30)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            PromotionContentLayout(forceVertical: dynamicTypeSize.isAccessibilitySize) {
                descriptionView
                actionButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(showsContent ? 1 : 0)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(Color.air.groupedItem)
                .overlay {
                    RoundedRectangle(cornerRadius: 26).fill(Color.air.primaryLabel.opacity(isHovering && !isActionHovering ? 0.04 : 0))
                }
                .overlay(alignment: .bottom) {
                    Image.airBundle("PromotionBackplate")
                        .resizable()
                        .colorMultiply(Color.air.groupedItem)
                        .frame(height: 32)
                        .opacity(showsContent ? 0 : 1)
                }
                .clipShape(.rect(cornerRadius: 26))
                .contentShape(.rect(cornerRadius: 26))
                .onTap(isPressedBinding: $isPressed) { onAction() }
                .disabled(isLoading)
                .onHover { isHovering = $0 }
                .accessibilityLabel("\(localized(banner.title)). \(String(description.characters))")
                .accessibilityHint(localized(banner.actionButton.title))
                .accessibilityIdentifier("promotion.body")
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image.airBundle("PromotionClose")
                    .resizable()
                    .frame(width: 12, height: 12)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang("Close"))
            .accessibilityIdentifier("promotion.dismiss")
            .padding(5)
            .opacity(showsContent ? 1 : 0)
        }
        .highlightScale(isPressed, scale: 0.98, isEnabled: !reduceMotion)
        .accessibilityElement(children: .contain)
    }

    private var descriptionView: some View {
        Text(description)
            .textStyle(.supporting, scaling: .dynamic)
            .tracking(-0.15)
            .lineSpacing(1)
            .foregroundStyle(Color.air.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var actionButton: some View {
        Button(action: onAction) {
            Text(verbatim: localized(banner.actionButton.title))
                .textStyle(.supportingBold, scaling: .dynamic)
                .tracking(-0.43)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(.tint)
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading { ProgressView().tint(.accentColor) }
                }
        }
        .buttonStyle(PromotionActionButtonStyle())
        .onHover { isActionHovering = $0 }
        .disabled(isLoading)
        .accessibilityIdentifier("promotion.action")
    }
}

private struct PromotionContentLayout: Layout {
    var forceVertical: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measurement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measurement = measurement(width: bounds.width, subviews: subviews)
        let descriptionY = measurement.isVertical ? bounds.minY : bounds.maxY - measurement.description.height - 8
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: descriptionY),
            anchor: .topLeading,
            proposal: ProposedViewSize(measurement.description)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.maxY),
            anchor: .bottomTrailing,
            proposal: ProposedViewSize(measurement.action)
        )
    }

    private func measurement(width proposedWidth: CGFloat?, subviews: Subviews) -> (size: CGSize, description: CGSize, action: CGSize, isVertical: Bool) {
        let idealAction = subviews[1].sizeThatFits(.unspecified)
        let width = proposedWidth.flatMap { $0.isFinite ? max(0, $0) : nil }
            ?? (subviews[0].sizeThatFits(.unspecified).width + 10 + idealAction.width)
        // Leave most of the row for the description; longer translations get their own button row.
        let isVertical = forceVertical || idealAction.width > width * 0.4
        let action = subviews[1].sizeThatFits(ProposedViewSize(width: min(idealAction.width, width), height: nil))
        let descriptionWidth = isVertical ? width : max(0, width - action.width - 10)
        let description = subviews[0].sizeThatFits(ProposedViewSize(width: descriptionWidth, height: nil))
        let height = isVertical ? description.height + 8 + action.height : max(description.height + 8, action.height)
        return (CGSize(width: width, height: height), description, action, isVertical)
    }
}

extension ApiPromotion.InfoBanner {
    func localized(_ text: String, isSensitiveDataHidden: Bool) -> String {
        var values = textValues ?? [:]
        if isSensitiveDataHidden, values["%amount%"] != nil {
            values["%amount%"] = "***"
        }
        switch text {
        case "🔒 %amount% %symbol% locked in another staking":
            if let amount = values["%amount%"], let symbol = values["%symbol%"] {
                // Keep the amount and ticker in one LTR run inside the localized sentence.
                return L10n.amountSymbolLockedInAnotherStaking(
                    amount: "\u{2066}\(amount)",
                    symbol: "\(symbol)\u{2069}"
                )
            }
        case "Tap to restake your %symbol% with higher returns.":
            if let symbol = values["%symbol%"] {
                return L10n.tapToRestakeYourSymbolWithHigherReturns(symbol: symbol)
            }
        default:
            break
        }
        return values.reduce(lang(text)) { result, entry in
            result.replacingOccurrences(of: entry.key, with: entry.value)
        }
    }
}

private struct PromotionActionButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.tint.opacity(configuration.isPressed || isHovering ? 0.2 : 0.1), in: .capsule)
            // Expand the tap target without adding space above short descriptions.
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .padding(.vertical, -7)
            .onHover { isHovering = $0 }
    }
}
