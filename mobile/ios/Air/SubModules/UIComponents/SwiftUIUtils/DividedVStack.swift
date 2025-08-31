
import SwiftUI

/// A vertical stack that adds separators
/// From https://movingparts.io/variadic-views-in-swiftui
public struct DividedVStack<Content: View>: View {
    var leadingMargin: CGFloat
    var trailingMargin: CGFloat
    var color: Color?
    var content: Content

    public init(
        leadingMargin: CGFloat = 0,
        trailingMargin: CGFloat = 0,
        color: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.leadingMargin = leadingMargin
        self.trailingMargin = trailingMargin
        self.color = color
        self.content = content()
    }

    public var body: some View {
        _VariadicView.Tree(
            DividedVStackLayout(
                leadingMargin: leadingMargin,
                trailingMargin: trailingMargin,
                color: color
            )
        ) {
            content
        }
    }
}

public struct DividedVStackLayout: _VariadicView_UnaryViewRoot {
    var leadingMargin: CGFloat
    var trailingMargin: CGFloat
    var color: Color?

    @ViewBuilder
    public func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id

        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                    .overlay(alignment: .bottom) {
                        if child.id != last {
                            Rectangle()
                                .fill(color ?? .air.menuSeparator)
                                .frame(height: 0.333)
                                .padding(.leading, leadingMargin)
                                .padding(.trailing, trailingMargin)
                        }
                    }

                if child.id != last {
                }
            }
        }
    }
}

