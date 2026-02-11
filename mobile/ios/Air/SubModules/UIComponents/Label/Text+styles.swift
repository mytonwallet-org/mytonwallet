import SwiftUI

public enum TextStyle {
    /// The default text label style which is 17ptRegular / system font's style .body
    case body17
    case header28
    
    var font: Font {
        switch self {
        case .header28: return .system(size: 28, weight: .semibold)
        case .body17: return .system(size: 17)
        }
    }
    
    var color: Color? {
        return nil
    }
    
    var lineSpacing: CGFloat? {
        return nil
    }
}

extension Text {
    public func style(_ style: TextStyle) -> some View {
        self
            .font(style.font)
            .if(style.color != nil) { view in
                view.foregroundColor(style.color!)
            }
            .if(style.lineSpacing != nil) { view in
                view.lineSpacing(style.lineSpacing!)
            }
    }
}
