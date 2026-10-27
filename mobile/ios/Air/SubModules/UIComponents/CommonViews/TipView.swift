import SwiftUI
import WalletContext

/// Tip content. WAlertController owns the glass surface and modal presentation.
public struct TipView<Content: View>: View {
    public enum Kind {
        case info
        case warning
        case danger
    }

    private let title: String
    private let kind: Kind
    private let content: () -> Content

    public init(title: String, kind: Kind = .info, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.kind = kind
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 10) {
            icon
                .padding(4)
                .accessibilityHidden(true)
            Text(title)
                .textStyle(.bodyStrong, scaling: .dynamic)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            content()
                .textStyle(.body, scaling: .dynamic)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .info:
            Image.airBundle("TipIcon")
                .foregroundStyle(.tint)
        case .warning, .danger:
            Image(systemName: "exclamationmark.circle.fill")
                .resizable()
                .frame(width: 36, height: 36)
                .foregroundStyle(kind == .danger ? Color.air.error : .orange)
        }
    }
}
