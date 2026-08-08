import SwiftUI

public struct CompactActionSummary<Icon: View, Label: View>: View {
    private let icon: Icon
    private let label: Label

    public init(
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder label: () -> Label
    ) {
        self.icon = icon()
        self.label = label()
    }

    public var body: some View {
        HStack(spacing: 4) {
            icon
                .frame(width: 20, height: 20)

            label
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .textStyle(.body)
        .foregroundStyle(.tint)
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

public extension CompactActionSummary where Icon == EmptyView {
    init(@ViewBuilder label: () -> Label) {
        self.init(icon: { EmptyView() }, label: label)
    }
}
