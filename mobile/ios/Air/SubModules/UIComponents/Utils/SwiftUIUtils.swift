import Foundation
import SwiftUI
import WalletContext

extension Text {
    public init(_ attr: NSAttributedString) {
        self.init(AttributedString(attr))
    }
}

extension View {
    
    @ViewBuilder
    public func writingToolsDisabled() -> some View {
        if #available(iOS 18.0, *) {
            self.writingToolsBehavior(.disabled)
        } else {
            self
        }
    }
    
    public func font13() -> some View {
        self
            .font(.footnote)
            .lineSpacing(2)
            .padding(.top, 2)
    }
    
    public func font14h18() -> some View {
        self
            .font(.system(size: 14))
            .lineSpacing(2)
            .padding(.top, 1)
    }
    
    public func font16h22() -> some View {
        self
            .font(.callout)
            .lineSpacing(3)
            .padding(.top, 2)
            .padding(.bottom, 1)
    }
    
    public func font17h22() -> some View {
        self
            .font(.body)
            .lineSpacing(1)
            .frame(minHeight: 22)
    }
    
    public func airFont15h18(weight: Font.Weight) -> some View {
        self
            .font(.system(size: 15, weight: weight))
            .frame(minHeight: 18)
    }
    
    public func airFont24h32(weight: Font.Weight) -> some View {
        self
            .font(.system(size: 24, weight: weight))
            .frame(minHeight: 32)
    }
    
    public func navigationBarInset(_ inset: CGFloat?) -> some View {
        self
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: inset)
            }
    }
    
    public func scrollPosition(ns: Namespace.ID, offset: CGFloat = 0, callback: @escaping (CGFloat) -> ()) -> some View {
        self.background {
            GeometryReader { geom in
                Color.clear
                    .onChange(of: geom.frame(in: .named(ns)).origin.y) { y in
                        callback(-y + offset)
                    }
            }
        }
    }
    
    @ViewBuilder
    public func highlightBackground(_ isHighlighted: Bool) -> some View {
        self.background {
            if isHighlighted {
                Color(WTheme.highlight)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.linear(duration: 0.1)),
                            removal: .opacity.animation(.linear(duration: 0.5))
                        )
                    )
            }
        }
    }
    
    @ViewBuilder
    public func highlightOverlay(_ isHighlighted: Bool) -> some View {
        self.overlay {
            if isHighlighted {
                Color.airBundle("DarkHighlightColor")
                    .blendMode(.multiply)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.linear(duration: 0.1)),
                            removal: .opacity.animation(.linear(duration: 0.5))
                        )
                    )
            }
        }
        .compositingGroup()
    }
    
    @ViewBuilder
    public func highlightScale(_ isHighlighted: Bool, scale: CGFloat, isEnabled: Bool) -> some View {
        self
            .scaleEffect(isHighlighted && isEnabled ? scale : 1)
            .animation(isHighlighted ? .smooth(duration: 0.3) : .smooth(duration: 0.25), value: isHighlighted)
    }
    
    @ViewBuilder
    public func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}


enum WindowSizeKey: EnvironmentKey {
    static var defaultValue: CGSize {
        MainActor.assumeIsolated { // Improvement: assumeIsolated can potentially crash, use safe constructs
            UIApplication.shared.sceneWindows.first?.bounds.size ?? .zero
        }
    }
}

public extension EnvironmentValues {
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

public extension View {
    
    func sourceAtop<V: View>(@ViewBuilder _ stylingView: () -> V) -> some View {
        self
            .overlay {
                stylingView()
                    .blendMode(.sourceAtop)
                    .allowsHitTesting(false)
            }
            .compositingGroup()
            }
    
    func scaleEffectIgnoredByLayout(_ scale: CGFloat) -> some View {
        self.modifier(_ScaleEffect(scale: CGSize(width: scale, height: scale)).ignoredByLayout())
    }

    func offsetIgnoredByLayout(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        self.modifier(_OffsetEffect(offset: CGSize(width: x, height: y)).ignoredByLayout())
    }
}
