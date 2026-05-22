import SwiftUI
import WalletContext
import UIComponents

struct WalletPickerOptionRow: View {

    private let iconCornerRadius: CGFloat = 8

    var icon: String
    var title: String
    var subtitle: String
    var showsDivider: Bool = false
    var onTap: () -> ()

    var body: some View {
        InsetButtonCell(horizontalPadding: 16, verticalPadding: 10, action: onTap) {
            HStack(spacing: 16) {
                WalletPickerIcon(icon: icon, cornerRadius: iconCornerRadius)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.air.primaryLabel)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image.airBundle("RightArrowIcon")
            }
            .frame(minHeight: 52)
            .backportGeometryGroup()
        }
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.air.separator)
                    .frame(height: 0.33)
                    .padding(.leading, 62)
                    .padding(.trailing, 16)
            }
        }
    }
}

private struct WalletPickerIcon: View {

    var icon: String
    var cornerRadius: CGFloat

    var body: some View {
        Image.airBundle(icon)
            .resizable()
            .frame(width: 30, height: 30)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(iconBorderGradient, lineWidth: 0.6)
            }
    }

    private var iconBorderGradient: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .white.opacity(0.18), location: 0.00),
                .init(color: .white.opacity(0.10), location: 0.20),
                .init(color: .white.opacity(0.35), location: 0.45),
                .init(color: .white.opacity(0.10), location: 0.70),
                .init(color: .white.opacity(0.20), location: 0.95),
                .init(color: .white.opacity(0.18), location: 1.00),
            ],
            center: .center,
            startAngle: .degrees(90),
            endAngle: .degrees(450)
        )
    }
}

struct WalletPickerSectionTitle: View {

    var body: some View {
        HStack(spacing: 12) {
            WalletPickerDivider()
            Text(lang("or import from"))
            WalletPickerDivider()
        }
        .font(.system(size: 17))
        .frame(height: 22)
        .padding(.vertical, 24)
        .foregroundStyle(Color.air.secondaryLabel)
        .frame(maxWidth: .infinity)
    }
}

private struct WalletPickerDivider: View {

    var body: some View {
        Capsule()
            .frame(width: 64, height: 0.667)
            .offset(y: 1.333)
            .opacity(0.3)
    }
}
