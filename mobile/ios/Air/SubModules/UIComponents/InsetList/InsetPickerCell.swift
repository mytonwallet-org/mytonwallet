import SwiftUI
import WalletContext

public struct InsetPickerCell<Selection: Hashable, Content: View>: View {
    private let title: String
    @Binding private var selection: Selection
    private let value: String
    private let content: Content
    @ScaledMetric(relativeTo: .body) private var arrowWidth = 10

    public init(
        _ title: String,
        selection: Binding<Selection>,
        value: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.value = value
        self.content = content()
    }

    public var body: some View {
        InsetDetailCell(horizontalPadding: 16, verticalPadding: 0) {
            Text(title)
                .foregroundStyle(Color.air.primaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .accessibilityHidden(true)
        } value: {
            Menu {
                Picker(title, selection: $selection) {
                    content
                }
                .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text(value)
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(1)
                    Image.airBundle("inline.picker")
                        .textStyle(.body, content: .technical, scaling: .dynamic)
                        .imageScale(.medium)
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .fixedSize()
                        .frame(width: arrowWidth)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(value)
        }
    }
}
