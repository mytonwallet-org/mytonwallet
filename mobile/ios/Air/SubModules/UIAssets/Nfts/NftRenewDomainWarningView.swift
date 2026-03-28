import SwiftUI
import WalletContext

struct NftRenewDomainWarningContent: Hashable, Sendable {
    let addresses: [String]
    let text: String
}

struct NftRenewDomainWarningView: View {
    let content: NftRenewDomainWarningContent
    let onTap: () -> Void
    let onClose: () -> Void

    private var attributedMessage: AttributedString {
        (try? AttributedString(markdown: content.text)) ?? AttributedString(content.text)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Text(attributedMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .layoutPriority(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .imageScale(.small)
                        .foregroundStyle(Color.white)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .systemRed).opacity(0.8))
        )
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    NftRenewDomainWarningStatesPreview()
}

@available(iOS 18, *)
private struct NftRenewDomainWarningStatesPreview: View {
    private struct PreviewState: Hashable {
        let title: String
        let content: NftRenewDomainWarningContent
    }

    private let states: [PreviewState] = [
        .init(
            title: "Single expiring today",
            content: .init(
                addresses: ["preview-single-today"],
                text: lang("$domain_expire", arg1: "soon.ton", arg2: lang("$in_days", arg1: 0))
            )
        ),
        .init(
            title: "Single expiring tomorrow",
            content: .init(
                addresses: ["preview-single-tomorrow"],
                text: lang(
                    "$domain_expire",
                    arg1: "a-very-long-domain-name-for-preview.ton",
                    arg2: lang("$in_days", arg1: 1)
                )
            )
        ),
        .init(
            title: "Single expired",
            content: .init(
                addresses: ["preview-single-expired"],
                text: lang("$domain_was_expired", arg1: "expired.ton")
            )
        ),
        .init(
            title: "Multiple expiring",
            content: .init(
                addresses: ["preview-multiple-expiring-1", "preview-multiple-expiring-2"],
                text: lang("$domains_expire", arg1: lang("$in_days", arg1: 5), arg2: 2)
            )
        ),
        .init(
            title: "Multiple expired",
            content: .init(
                addresses: ["preview-multiple-expired-1", "preview-multiple-expired-2", "preview-multiple-expired-3"],
                text: lang("$domains_was_expired", arg1: 3)
            )
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(states, id: \.self) { state in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.air.secondaryLabel)
                        NftRenewDomainWarningView(
                            content: state.content,
                            onTap: {},
                            onClose: {}
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background {
            Color.air.pickerBackground.ignoresSafeArea()
        }
    }
}
#endif
