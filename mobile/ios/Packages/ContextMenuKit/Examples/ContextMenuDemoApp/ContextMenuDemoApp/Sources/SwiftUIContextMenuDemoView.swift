import SwiftUI
import ContextMenuKit

@available(iOS 16.0, *)
struct SwiftUIContextMenuDemoView: View {
    let portalConfiguration: () -> ContextMenuConfiguration
    let plainConfiguration: () -> ContextMenuConfiguration
    let portalSourceViewProvider: (() -> UIView?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14.0) {
            Text("SwiftUI Sources")
                .font(.system(size: 22.0, weight: .bold))

            Text("These controls open the same extracted menu stack from SwiftUI-hosted source views. The first keeps the source visible through a portal clone above the backdrop.")
                .font(.system(size: 15.0, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12.0) {
                SwiftUIContextMenuCard(
                    eyebrow: "Portal Source",
                    title: "Tap or hold the SwiftUI pill",
                    detail: "The menu is anchored from SwiftUI and keeps the source visible with a portal clone."
                )
                .contextMenuSource(
                    triggers: [.tap, .longPress],
                    sourcePortal: ContextMenuSourcePortal(
                        sourceViewProvider: portalSourceViewProvider,
                        mask: .roundedAttachmentRect(cornerRadius: 22.0, cornerCurve: .continuous)
                    ),
                    configuration: portalConfiguration
                )

                SwiftUIContextMenuCard(
                    eyebrow: "Plain Source",
                    title: "Same source path without the portal",
                    detail: "Useful for parity checks when only the anchor rect matters."
                )
                .contextMenuSource(
                    triggers: [.tap, .longPress],
                    configuration: plainConfiguration
                )
            }
        }
        .padding(18.0)
        .background(
            RoundedRectangle(cornerRadius: 28.0, style: .continuous)
                .fill(Color(uiColor: UIColor.white.withAlphaComponent(0.72)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28.0, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1.0)
        )
    }
}

@available(iOS 16.0, *)
private struct SwiftUIContextMenuCard: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12.0) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.66, blue: 0.95),
                            Color(red: 0.18, green: 0.46, blue: 0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38.0, height: 38.0)
                .overlay(
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15.0, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4.0) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11.0, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.5))

                Text(title)
                    .font(.system(size: 16.0, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.92))

                Text(detail)
                    .font(.system(size: 13.0, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8.0)

            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 18.0, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.45))
        }
        .padding(.horizontal, 16.0)
        .padding(.vertical, 14.0)
        .background(
            RoundedRectangle(cornerRadius: 22.0, style: .continuous)
                .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
        )
    }
}
