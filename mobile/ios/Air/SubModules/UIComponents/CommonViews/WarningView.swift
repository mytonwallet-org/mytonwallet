
import SwiftUI
import WalletContext


public struct WarningView: View {
    
    public var header: String?
    public var text: String
    
    public enum Kind {
        case error
        case warning
        
        var color: Color {
            switch self {
            case .error:
                Color(WTheme.error)
            case .warning:
                Color.orange
            }
        }
    }
    public var kind: Kind
    
    public init(header: String? = nil, text: String, kind: Kind = .error) {
        self.header = header
        self.text = text
        self.kind = kind
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let header {
                Text(LocalizedStringKey(header))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(LocalizedStringKey(text))
                .frame(maxWidth: .infinity, alignment: .leading)
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
}
