import SwiftUI
import UIComponents
import WalletContext
import WalletCore

/// The caller owns ordering, dismissal, and navigation. Only the first banner is interactive.
public struct HomePromotionStack: View {
    public var promotions: [ApiPromotion]
    public var animation: Animation?
    public var transition: AnyTransition
    public var onAction: (ApiPromotion) -> Void
    public var onDismiss: (ApiPromotion) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        onAction: @escaping (ApiPromotion) -> Void,
        onDismiss: @escaping (ApiPromotion) -> Void
    ) {
        self.promotions = promotions
        self.animation = animation
        self.transition = transition
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let banners = promotions.filter { $0.kind == .infoBanner && $0.infoBanner != nil }
        let hasNextBanner = banners.count > 1
        ZStack(alignment: .top) {
            if let promotion = banners.first, let banner = promotion.infoBanner {
                // Reserve the front card's natural height without letting hidden cards affect it.
                HomePromotionBanner(
                    banner: banner,
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
                                showsContent: index == 0,
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
    var showsContent = true
    let onAction: () -> Void
    let onDismiss: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 14

    private var description: AttributedString {
        var text = (try? AttributedString(
            markdown: banner.description,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(banner.description)
        for run in text.runs {
            // Banner navigation belongs to the whole card, including emphasized text.
            text[run.range].link = nil
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                text[run.range].font = .system(size: bodySize, weight: .semibold)
            }
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: banner.title)
                .font(.system(size: titleSize, weight: .medium))
                .tracking(-0.43)
                .foregroundStyle(Color.air.primaryLabel)
                .frame(minHeight: 22, alignment: .leading)
                .padding(.trailing, 30)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    descriptionView
                    actionButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    descriptionView
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                    actionButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(showsContent ? 1 : 0)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(Color.air.groupedItem)
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
                .accessibilityLabel("\(banner.title). \(String(description.characters))")
                .accessibilityHint(banner.actionButton.title)
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
            .font(.system(size: bodySize))
            .tracking(-0.15)
            .lineSpacing(1)
            .foregroundStyle(Color.air.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var actionButton: some View {
        Button(action: onAction) {
            Text(verbatim: banner.actionButton.title)
                .font(.system(size: bodySize, weight: .bold))
                .tracking(-0.43)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(.tint)
        }
        .buttonStyle(PromotionActionButtonStyle())
        .accessibilityIdentifier("promotion.action")
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
