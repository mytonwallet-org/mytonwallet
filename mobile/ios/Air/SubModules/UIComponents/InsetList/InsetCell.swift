import SwiftUI
import WalletContext


public struct InsetCell<Content: View>: View {
    
    public var horizontalPadding: CGFloat?
    public var verticalPadding: CGFloat?
    public var content: Content
    
    public init(horizontalPadding: CGFloat? = nil, verticalPadding: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }
    
    public var body: some View {
        content
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, verticalPadding ?? 11)
            .padding(.horizontal, horizontalPadding ?? (IOS_26_MODE_ENABLED ? 20 : 16))
            .frame(minHeight: IOS_26_MODE_ENABLED ? 52 : nil)
    }
}


public struct InsetDetailCell<Label: View, Value: View>: View {
    
    public var alignment: VerticalAlignment
    public var horizontalPadding: CGFloat?
    public var verticalPadding: CGFloat?
    public var label: Label
    public var value: Value
    
    public init(alignment: VerticalAlignment = .center, horizontalPadding: CGFloat? = nil, verticalPadding: CGFloat? = nil, @ViewBuilder label: @escaping () -> Label, @ViewBuilder value: @escaping () -> Value) {
        self.alignment = alignment
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.label = label()
        self.value = value()
    }
    
    public var body: some View {
        InsetCell(horizontalPadding: horizontalPadding, verticalPadding: verticalPadding) {
            HStack(alignment: alignment, spacing: 0) {
                label
                Spacer(minLength: 4)
                value
            }
        }
    }
}


public struct InsetButtonCell<Label: View>: View {
    
    public var alignment: Alignment
    public var horizontalPadding: CGFloat?
    public var verticalPadding: CGFloat?
    public var action: () -> ()
    public var label: Label
    
    @State private var isTouching = false
    
    public init(alignment: Alignment = .leading, horizontalPadding: CGFloat? = nil, verticalPadding: CGFloat? = nil, action: @escaping () -> (), @ViewBuilder label: @escaping () -> Label) {
        self.alignment = alignment
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.action = action
        self.label = label()
    }
    
    public var body: some View {
        Button(action: action) {
            InsetCell(horizontalPadding: horizontalPadding, verticalPadding: verticalPadding) {
                label
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .foregroundStyle(Color(WTheme.tint))
                    .tint(Color(WTheme.tint))
            }
            .contentShape(.rect)
        }
        .highlightBackground(isTouching)
        .touchGesture($isTouching)
        .buttonStyle(InsetButtonStyle())
    }
}

public struct InsetButtonStyle: SwiftUI.ButtonStyle {
    
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}


public struct InsetExpandableCell: View {
    
    public var horizontalPadding: CGFloat?
    public var verticalPadding: CGFloat?
    var content: String
    
    @State private var isExpanded = false
    
    public init(horizontalPadding: CGFloat? = nil, verticalPadding: CGFloat? = nil, content: String, isExpanded: Bool = false) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content
        self.isExpanded = isExpanded
    }
    
    public var body: some View {
        InsetCell(horizontalPadding: horizontalPadding, verticalPadding: verticalPadding) {
            ViewThatFits(in: .horizontal) {
                Text(verbatim: content)
                    .lineLimit(1)

                HStack(spacing: 16) {
                    Text(verbatim: content)
                        .lineLimit(isExpanded ? 20 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if !isExpanded {
                        Button(action: {isExpanded = true}) {
                            Text(lang("Show All").lowercased())
                                .tint(Color(WTheme.tint))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
