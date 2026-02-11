
import SwiftUI
import UIKit
import WalletContext
import Perception

public struct SegmentedControl: View {
    
    let model: SegmentedControlModel
    
    @Namespace private var ns
    
    @AppStorage("debug_hideSegmentedControls") private var hideSegmentedControls = false
    
    public init(model: SegmentedControlModel) {
        self.model = model
    }
    
    public var body: some View {
        if !hideSegmentedControls {
            Color.clear
                .overlay {
                    WithPerceptionTracking {
                        ZStack {
                            if model.isScrollingRequired {
                                ScrollView(.horizontal) {
                                    _SegmentedControlContent(model: model, ns: ns)
                                }
                                .backportScrollClipDisabled()
                                .backportScrollBounceBehaviorBasedOnSize()
                                .backportContentMargins(SegmentedControlConstants.scrollContentMargin)
                                .scrollIndicators(.hidden)
                            } else {
                                _SegmentedControlContent(model: model, ns: ns)
                                    .fixedSize()
                                    .frame(maxWidth: .infinity)
                            }
                        }.padding(.top, SegmentedControlConstants.topInset)
                    }
                    .overlay {
                        SegmentedControlReordering(model: model)
                    }
                }
        } else {
            Color.blue
        }
    }
}

struct _SegmentedControlContent: View {
    
    var model: SegmentedControlModel
    var ns: Namespace.ID
    
    var body: some View {
        SegmentedControlLayer(model: model, ns: ns)
            .foregroundStyle(Color(model.primaryColor))
            .background(alignment: .leading) {
                SegmentedControlSelectionView(model: model, ns: ns)
            }
            .font(model.font)
            .coordinateSpace(name: ns)
    }
}


struct SegmentedControlSelectionView: View {
    
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

enum SegmentedControlConstants {
    static let spacing: CGFloat = 8
    /// Height of tab (text, capsule) view.
    static let height: CGFloat = 24
    /// Extra space over tabs to place "delete" button thumbnails in reordering
    static let topInset: CGFloat = 9
    static let innerPadding: CGFloat = 10
    static let accessoryWidth: CGFloat = 9.333
    static let scrollContentMargin: CGFloat = 16
    static var fullHeight: CGFloat { height + topInset }
}
