import UIKit
import SwiftUI
import WalletContext

public struct WUIButtonStyle: PrimitiveButtonStyle {
    public var style: WButtonStyle
    public var loadingIndicatorDelay: CGFloat = 0.2
    public var useLegacyShadow: Bool

    public init(style: WButtonStyle, useLegacyShadow: Bool = false) {
        self.style = style
        self.useLegacyShadow = useLegacyShadow
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isLoading) private var isLoading

    public func makeBody(configuration: Configuration) -> some View {
        WUIButtonStyleView(
            style: style,
            isEnabled: isEnabled,
            isLoading: isLoading,
            loadingIndicatorDelay: loadingIndicatorDelay,
            useLegacyShadow: useLegacyShadow,
            label: styledLabel(configuration: configuration),
            action: configuration.trigger
        )
        .id(style)
        .frame(height: WButton.height(for: style))
        .applyModifierConditionally {
            if style == .compactCapsule {
                $0.fixedSize(horizontal: true, vertical: false)
            } else {
                $0.frame(maxWidth: .infinity)
            }
        }
        .accessibilityRepresentation {
            Button(action: configuration.trigger) { configuration.label }
                .buttonStyle(.plain)
                .disabled(!isEnabled || isLoading)
        }
    }

    @ViewBuilder
    private func styledLabel(configuration: Configuration) -> some View {
        if style == .compactCapsule {
            configuration.label.labelStyle(WUICompactButtonLabelStyle())
        } else {
            configuration.label
        }
    }
}

private struct WUIButtonStyleView<Label: View>: UIViewRepresentable {
    @Environment(\.self) private var environment
    let style: WButtonStyle
    let isEnabled: Bool
    let isLoading: Bool
    let loadingIndicatorDelay: CGFloat
    let useLegacyShadow: Bool
    let label: Label
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WButton {
        let button = WButton(style: style)
        let contentView = makeLabelConfiguration(button: button, coordinator: context.coordinator).makeContentView()
        context.coordinator.contentView = contentView
        button.setCustomContentView(contentView)
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: WButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.canPress = isEnabled && !isLoading
        button.isEnabled = isEnabled
        button.isUserInteractionEnabled = context.coordinator.canPress
        context.coordinator.contentView?.configuration = makeLabelConfiguration(button: button, coordinator: context.coordinator)
        button.invalidateIntrinsicContentSize()
        button.setNeedsLayout()
        if useLegacyShadow && !IOS_26_MODE_ENABLED {
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
            button.layer.shadowRadius = 8
            button.layer.shadowOpacity = 0.12
        }
        context.coordinator.updateLoading(isLoading, button: button, delay: loadingIndicatorDelay)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: WButton.height(for: style))
    }

    private func makeLabelConfiguration(button: WButton, coordinator: Coordinator) -> UIHostingConfiguration<some View, EmptyView> {
        UIHostingConfiguration {
            // Hosted labels can change their ideal size without an `updateUIView` call
            WUIButtonLabelLayout(onSizeChange: { [weak button, weak coordinator] size in
                DispatchQueue.main.async {
                    guard let button, let coordinator else { return }
                    coordinator.updateContentSize(size, button: button)
                }
            }) {
                label
                    .font(Font(WButton.font(for: style)))
                    .applyModifierConditionally {
                        if style == .primary && isEnabled && button.usesGlassButtonStyling {
                            $0.foregroundForTintedBackground()
                        } else {
                            $0.foregroundStyle(Color(button.contentForegroundColor))
                        }
                    }
                    .lineLimit(1)
                    .environment(\.isEnabled, isEnabled)
                    .environment(\.self, environment)
            }
        }
        .margins(.all, 0)
    }

    @MainActor final class Coordinator: NSObject {
        var contentView: (UIView & UIContentView)?
        var action: (() -> Void)?
        var canPress = false
        private var contentSize: CGSize?
        private var isLoading = false
        private var loadingTask: Task<Void, Never>?

        func updateContentSize(_ size: CGSize, button: WButton) {
            guard contentSize != size else { return }
            contentSize = size
            button.invalidateIntrinsicContentSize()
            button.setNeedsLayout()
        }

        func updateLoading(_ isLoading: Bool, button: WButton, delay: CGFloat) {
            guard self.isLoading != isLoading else { return }
            self.isLoading = isLoading
            loadingTask?.cancel()
            if isLoading && delay > 0 {
                loadingTask = Task { [weak button] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    button?.showLoading = true
                }
            } else {
                button.showLoading = isLoading
            }
        }

        @objc func pressed() {
            guard canPress else { return }
            action?()
        }
    }
}

private struct WUIButtonLabelLayout: Layout {
    let onSizeChange: (CGSize) -> Void

    func makeCache(subviews: Subviews) -> CGSize { .zero }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CGSize) -> CGSize {
        let label = subviews.first
        let idealSize = label?.sizeThatFits(.unspecified) ?? .zero
        if cache != idealSize {
            cache = idealSize
            onSizeChange(idealSize)
        }
        return label?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CGSize) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: proposal)
    }
}

private struct WUICompactButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .textStyle(.calloutEmphasized, content: .technical)
                .frame(width: 24, height: 22)
            configuration.title
        }
    }
}

public extension PrimitiveButtonStyle where Self == WUIButtonStyle {
    static var airPrimary: WUIButtonStyle { WUIButtonStyle(style: .primary) }
    static var airSecondary: WUIButtonStyle { WUIButtonStyle(style: .secondary) }
    static var airCompactCapsule: WUIButtonStyle { WUIButtonStyle(style: .compactCapsule) }
    static var airSecondaryDestructive: WUIButtonStyle {  WUIButtonStyle(style: .thickDestructiveCapsule) }
    static var airClearBackground: WUIButtonStyle { WUIButtonStyle(style: .clearBackground) }
    
    func withLegacyShadow() -> WUIButtonStyle {
        var result = self
        result.useLegacyShadow = true
        return result
    }
}

public extension EnvironmentValues {
    @Entry var isLoading = false
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("Loading") {
    @Previewable @State var isLoading = false

    Button(action: {}) {
        Text("Hello")
    }
    .buttonStyle(.airPrimary)
    .environment(\.isLoading, isLoading)
    .padding()
    .task {
        isLoading = false
        try? await Task.sleep(for: .seconds(2))
        isLoading = true
        try? await Task.sleep(for: .seconds(2))
        isLoading = false
        try? await Task.sleep(for: .seconds(2))
        isLoading = true
    }
}

@available(iOS 17.0, *)
#Preview("All Styles") {
    @Previewable @State var isLoading = true
    
    let styles: [(String, WUIButtonStyle)] = [
        ("Primary", .airPrimary),
        ("Secondary", .airSecondary),
        ("Compact Capsule", .airCompactCapsule),
        ("Secondary Destructive", .airSecondaryDestructive),
        ("Secondary Destructive Shadow", .airSecondaryDestructive.withLegacyShadow()),
        ("Clear", .airClearBackground),
    ]

    ScrollView {
        VStack(spacing: 24) {
            ForEach(styles, id: \.0) { name, style in
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .textStyle(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button(action: {}) { Text("Enabled") }
                            .buttonStyle(style)

                        Button(action: {}) {
                            Label("Icon", systemImage: "plus.square.on.square")
                        }
                        .buttonStyle(style)

                        Button(action: {}) { Text("Disabled") }
                            .buttonStyle(style)
                            .disabled(true)
                        
                        Button(action: {}) { Text("Loading") }
                            .buttonStyle(style)
                            .disabled(true)
                            .environment(\.isLoading, isLoading)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
    }
}
#endif
