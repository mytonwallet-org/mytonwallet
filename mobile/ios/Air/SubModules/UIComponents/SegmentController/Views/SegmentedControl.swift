
import SwiftUI
import UIKit
import WalletContext
import Perception

public struct SegmentedControl: View {
    
    let model: SegmentedControlModel
    let scrollContentMargin: CGFloat
    
    @State private var scrollDebounceToken: Int = 0

    @Namespace private var ns

    @AppStorage("debug_hideSegmentedControls") private var hideSegmentedControls = false

    public init(model: SegmentedControlModel, scrollContentMargin: CGFloat) {
        self.model = model
        self.scrollContentMargin = scrollContentMargin
    }
            
    public var body: some View {
        if !hideSegmentedControls {
            Color.clear
                .overlay {
                    WithPerceptionTracking {
                        ScrollViewReader { proxy in
                            GeometryReader { geo in
                                WithPerceptionTracking {
                                    let contentFits = model.calculateContentWidth(includeBackground: false) <= geo.size.width
                                    ScrollView(.horizontal) {
                                        _SegmentedControlContent(model: model, ns: ns)
                                            .fixedSize()
                                            .padding(.horizontal, scrollContentMargin)
                                            .frame(minWidth: geo.size.width, alignment: .center)
                                    }
                                    .backportScrollClipDisabled()
                                    .backportScrollBounceBehaviorBasedOnSize()
                                    .scrollDisabled(contentFits)
                                    .scrollIndicators(.hidden)
                                    .onChange(of: model.selectedItem?.id) { _ in
                                        scrollDebounceToken &+= 1
                                    }
                                    .task(id: scrollDebounceToken) {
                                        guard scrollDebounceToken > 0 else { return }
                                        try? await Task.sleep(for: .milliseconds(80))
                                        guard !Task.isCancelled, let id = model.selectedItem?.id else { return }
                                        withAnimation(.smooth(duration: 0.35)) {
                                            proxy.scrollTo(id)
                                        }
                                    }
                                }
                            }
                        }
                        .opacity(model.isReordering ? 0.0 : 1.0)
                        .clipShape(RoundedRectangle(cornerRadius: model.constants.height / 2, style: .continuous))
                        .padding(model.constants.backgroundPadding)
                        .background { _SegmentedControlBackground(model: model, ns: ns) }
                        .padding(.top, model.constants.topInset)
                        .overlay {
                            SegmentedControlReordering(model: model, scrollContentMargin: scrollContentMargin)
                        }
                    }
                }
        } else {
            Color.blue
        }
    }
}

private struct _SegmentedControlBackground: View {
    
    var model: SegmentedControlModel
    var ns: Namespace.ID
    
    var body: some View {
        let padding = model.constants.backgroundPadding
        let cornerRadius = (model.constants.height + padding * 2) / 2
        
        switch model.backgroundStyle {
        case .none:
            EmptyView()
            
        case .colorHeader:
            if #available(iOS 26, *) {
                Color.clear
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.1))
                    }
            } else if #available(iOS 17, *) {
                ThinGlass(
                    cornerRadius: cornerRadius,
                    fillColor: .white.withAlphaComponent(0.05)
                )
            } else {
                // iOS 16 has issues with continuous paths in ThinGlass view for given radiuses (~20). A quick patch for outgoing iOS
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.7)
                    }
            }
            
        case .header:
            if #available(iOS 26, *) {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if #available(iOS 17, *) {
                Capsule(style: .continuous)
                    .fill(Color.air.sheetBackground)
                    .overlay {
                        ThinGlass(
                            cornerRadius: cornerRadius,
                            fillColor: .white.withAlphaComponent(0.05)
                        )
                    }
                    .shadow(style: .light)
            } else {
                Capsule(style: .continuous)
                    .fill(Color.air.sheetBackground)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.7)
                    }
                    .shadow(style: .light)
            }
        }
    }
}

private struct _SegmentedControlContent: View {
    
    var model: SegmentedControlModel
    var ns: Namespace.ID
    
    var body: some View {
        SegmentedControlLayer(model: model, ns: ns)
            .foregroundStyle(Color(model.primaryColor))
            .background(alignment: .leading) {
                SegmentedControlSelectionView(model: model, ns: ns)
            }
            .font(Font(model.font))
            .coordinateSpace(name: ns)
    }
}


private struct SegmentedControlSelectionView: View {
    
    let model: SegmentedControlModel
    
    var ns: Namespace.ID
    
    var body: some View {
        WithPerceptionTracking {
            if let frame = model.selectionFrame {
                Capsule()
                    .fill(Color(model.capsuleColor))
                    .matchedGeometryEffect(id: "capsule", in: ns, properties: .frame, anchor: .center, isSource: true)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)
            }
        }
    }
}

enum SegmentedControlBackgroundStyle {
    case none, colorHeader, header
}

public enum SegmentedControlStyle {
    case regular
    case colorHeader
    case header
}

struct SegmentedControlConstants {
    var spacing: CGFloat = 8
    /// Height of tab (text, capsule) view.
    var height: CGFloat = 24
    /// Extra space over tabs to place "delete" button thumbnails in reordering
    var topInset: CGFloat = 9
    var innerPadding: CGFloat = 10
    let accessoryWidth: CGFloat = 9.333
    var backgroundPadding: CGFloat = 0
    
    var labelGap: CGFloat { innerPadding }
    var fullHeight: CGFloat { height + topInset }
    var fullHeightWithBackground: CGFloat { fullHeight + backgroundPadding * 2 }
}

