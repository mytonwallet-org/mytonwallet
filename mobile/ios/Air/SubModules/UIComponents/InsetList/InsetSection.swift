
import SwiftUI
import WalletContext


public struct InsetSection<Content: View, Header: View, Footer: View>: View {
    
    public var backgroundColor: UIColor?
    public var addDividers: Bool
    public var horizontalPadding: CGFloat?
    public var dividersInset: CGFloat

    @ViewBuilder
    public var content: Content
    
    @ViewBuilder
    public var header: Header
    
    @ViewBuilder
    public var footer: Footer
    
    @Environment(\.insetListContext) private var insetListContext
    
    public init(backgroundColor: UIColor? = nil,
                addDividers: Bool = true,
                dividersInset: CGFloat = 0,
                horizontalPadding: CGFloat? = nil,
                @ViewBuilder content: @escaping () -> Content,
                @ViewBuilder header: @escaping () -> Header,
                @ViewBuilder footer: @escaping () -> Footer) {
        self.backgroundColor = backgroundColor
        self.addDividers = addDividers
        self.dividersInset = dividersInset
        self.horizontalPadding = horizontalPadding
        self.content = content()
        self.header = header()
        self.footer = footer()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .font(IOS_26_MODE_ENABLED ? .system(size: 17, weight: .semibold) : .system(size: 13))
                .textCase(IOS_26_MODE_ENABLED ? nil : .uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, IOS_26_MODE_ENABLED ? 20 : 16)
                .padding(.top, IOS_26_MODE_ENABLED ? 4 : 7)
                .padding(.bottom, 5)

            ZStack {
                Color(resolvedBackgroundColor)
                ContentContainer(addDividers: addDividers, dividersInset: dividersInset) {
                    content
                }
            }
            .clipShape(.rect(cornerRadius: S.insetSectionCornerRadius, style: .continuous))
                
            footer
                .font13()
                .foregroundStyle(.secondary)
                .padding(.horizontal, IOS_26_MODE_ENABLED ? 20 : 16)
                .padding(.top, IOS_26_MODE_ENABLED ? 8 : 7)
                .padding(.bottom, IOS_26_MODE_ENABLED ? 6 : 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalPadding ?? 16)
    }
    
    private var resolvedBackgroundColor: UIColor {
        backgroundColor ?? WTheme.groupedItem
    }
    
    private struct ContentContainer<_Content: View>: View {
        
        var addDividers: Bool
        var dividersInset: CGFloat

        var content: _Content
        
        init(addDividers: Bool, dividersInset: CGFloat, @ViewBuilder content: () -> _Content) {
            self.addDividers = addDividers
            self.dividersInset = dividersInset
            self.content = content()
        }
        
        var body: some View {
            _VariadicView.Tree(ContentLayout(addDividers: addDividers, dividersInset: dividersInset)) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private struct ContentLayout: _VariadicView_UnaryViewRoot {

        var addDividers: Bool = true
        var dividersInset: CGFloat

        @ViewBuilder
        func body(children: _VariadicView.Children) -> some View {
            let last = children.last?.id

            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { child in
                    child
                        .overlay(alignment: .bottom) {   
                            if addDividers && child.id != last {
                                InsetDivider()
                                    .padding(.leading, dividersInset)
                            }
                        }
                }
            }
        }
    }
}

extension InsetSection where Header == EmptyView {

    public init(backgroundColor: UIColor? = nil,
                addDividers: Bool = true,
                dividersInset: CGFloat = 0,
                horizontalPadding: CGFloat? = nil,
                @ViewBuilder content: @escaping () -> Content,
                @ViewBuilder footer: @escaping () -> Footer) {
        self.backgroundColor = backgroundColor
        self.addDividers = addDividers
        self.dividersInset = dividersInset
        self.horizontalPadding = horizontalPadding
        self.content = content()
        self.header = EmptyView()
        self.footer = footer()
    }
}

extension InsetSection where Footer == EmptyView {

    public init(backgroundColor: UIColor? = nil,
                addDividers: Bool = true,
                dividersInset: CGFloat = 0,
                horizontalPadding: CGFloat? = nil,
                @ViewBuilder content: @escaping () -> Content,
                @ViewBuilder header: @escaping () -> Header) {
        self.backgroundColor = backgroundColor
        self.addDividers = addDividers
        self.dividersInset = dividersInset
        self.horizontalPadding = horizontalPadding
        self.content = content()
        self.header = header()
        self.footer = EmptyView()
    }
}

extension InsetSection where Header == EmptyView, Footer == EmptyView {

    public init(backgroundColor: UIColor? = nil,
                addDividers: Bool = true,
                dividersInset: CGFloat = 0,
                horizontalPadding: CGFloat? = nil,
                @ViewBuilder content: @escaping () -> Content) {
        self.backgroundColor = backgroundColor
        self.addDividers = addDividers
        self.dividersInset = dividersInset
        self.horizontalPadding = horizontalPadding
        self.content = content()
        self.header = EmptyView()
        self.footer = EmptyView()
    }
}
