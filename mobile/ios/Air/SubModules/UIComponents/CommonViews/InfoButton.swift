import SwiftUI
import WalletContext

public struct InfoButton: View {
    private let title: String
    private let message: String
    private let offset: CGSize

    public init(title: String, message: String, offset: CGSize = CGSize(width: 22, height: 1.333)) {
        self.title = title
        self.message = message
        self.offset = offset
    }

    public var body: some View {
        Button(action: showInfo) {
            Image.airBundle("InfoIcon")
                .renderingMode(.template)
                .foregroundStyle(Color(.air.secondaryLabel.withAlphaComponent(0.3)))
                .padding(4)
                .contentShape(.circle)
        }
        .padding(-4)
        .buttonStyle(.plain)
        .offset(offset)
        .accessibilityLabel(title)
        .accessibilityHint(lang("Shows more information"))
    }

    private func showInfo() {
        topWViewController()?.showTip(title: title) {
            Text(langMd(message))
        }
    }
}
