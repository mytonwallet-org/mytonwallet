import SwiftUI

private let amountIconRowIconBaselineInset: CGFloat = 5

public struct AmountIconRow<Amount: View, Icon: View>: View {
    private let spacing: CGFloat
    private let showsIcon: Bool
    private let iconSize: CGFloat
    private let amount: () -> Amount
    private let icon: () -> Icon

    public init(
        spacing: CGFloat = 8,
        showsIcon: Bool = true,
        iconSize: CGFloat = 28,
        @ViewBuilder amount: @escaping () -> Amount,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.spacing = spacing
        self.showsIcon = showsIcon
        self.iconSize = iconSize
        self.amount = amount
        self.icon = icon
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            amount()
                .layoutPriority(1)

            if showsIcon {
                icon()
                    .frame(width: iconSize, height: iconSize)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions.height - amountIconRowIconBaselineInset
                    }
            }
        }
    }
}

public extension AmountIconRow where Icon == EmptyView {
    init(
        spacing: CGFloat = 8,
        @ViewBuilder amount: @escaping () -> Amount
    ) {
        self.init(spacing: spacing, showsIcon: false, iconSize: 0, amount: amount) {
            EmptyView()
        }
    }
}
