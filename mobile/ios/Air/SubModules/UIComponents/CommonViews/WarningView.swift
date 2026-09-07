
import SwiftUI
import WalletContext


public struct WarningView: View {
    
    public var header: String?
    public var text: String
    public var actionTitle: String?
    public var onAction: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    public enum Kind {
        case error
        case warning
        case info
        
        var color: Color {
            switch self {
            case .error:
                .air.error
            case .warning:
                Color.orange
            case .info:
                Color.blue
            }
        }
    }
    public var kind: Kind
    
    public init(header: String? = nil, text: String, kind: Kind = .error, actionTitle: String? = nil, onAction: (() -> Void)? = nil) {
        self.header = header
        self.text = text
        self.kind = kind
        self.actionTitle = actionTitle
        self.onAction = onAction
    }
    
    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    textContent
                    actionButton
                }
            } else {
                HStack(spacing: 12) {
                    textContent
                    actionButton
                }
            }
        }
        .multilineTextAlignment(.leading)
        .foregroundStyle(kind.color)
        .font13()
//            .font14h18()
        .padding(.bottom, 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(kind.color)
                .frame(width: 4)
        }
        .background(kind.color.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let header {
                Text(LocalizedStringKey(header))
                    .textStyle(.footnoteStrong, scaling: .dynamic)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(LocalizedStringKey(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var actionButton: some View {
        if let actionTitle, let onAction {
            Button(action: onAction) {
                Text(actionTitle)
                    .textStyle(.footnoteStrong, scaling: .dynamic)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(kind.color.opacity(0.12), in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}
