
import SwiftUI
import UIKit
import WalletContext
import Perception

extension SegmentedControlItem: DragulaItem {
    public func getItemProvider() -> NSItemProvider {
        NSItemProvider(item: id as NSString, typeIdentifier: "public/item")
    }
}

struct SegmentedControlReordering: View {
    
    let model: SegmentedControlModel
    
    var body: some View {
        WithPerceptionTracking {
            if model.isReordering {
                ZStack {
                    Color(WTheme.groupedItem)
                        .padding(.vertical, -2) // fully hide main content
                    content
                }
            }
        }
    }
    
    @ViewBuilder
    var content: some View {
        @Perception.Bindable var model = model
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                DragulaView(items: $model.items) { item in
                    ZStack {
                        Text(item.title)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 2)
                            .allowsHitTesting(false)
                            .shake()
                        
                        Color.clear.contentShape(.rect)
                    }
                } dropView: { item in
                    ZStack {
                        Text(item.title)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 2)
                            .allowsHitTesting(false)
                        
                        Color.clear.contentShape(.rect)
                    }
                    .opacity(0.5)
                } dropCompleted: {
                }
            }
        }
        .scrollIndicators(.hidden)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Color(WTheme.secondaryLabel))
        .overlay(alignment: .trailing) {
            Button(action: { model.stopReordering() }) {
                Text(lang("Done"))
                    .font(.system(size: 14, weight: .medium))
                    .padding(.vertical, 2)
                    .padding(.trailing, 6)
                    .padding(.leading, 12)
                    .foregroundStyle(Color(WTheme.tint))
                    .frame(height: SegmentedControlConstants.height)
                    .contentShape(.rect)
                    .background(
                        Rectangle()
                            .fill(Color(WTheme.groupedItem))
                            .opacity(0.9)
                    )
            }
        }
    }
}


extension View {
    
    /// Shakes the view horizontally, emulating the classic wrong-password wobble.
    @ViewBuilder
    func shake() -> some View {
        if #available(iOS 17.0, *) {
            modifier(_ShakeModifier())
        } else {
            self
        }
    }
}

// MARK: – Implementation details

@available(iOS 17, *)
private struct _ShakeModifier: ViewModifier {

    private struct Values: Equatable {
        var degrees: Double = 0
    }

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(
                initialValue: Values(),
                repeating: true,
            ) { view, value in
                view.rotationEffect(.degrees(value.degrees))
            } keyframes: { v in
                KeyframeTrack(\.degrees) {
                    LinearKeyframe(-2, duration: 0.15)
                    LinearKeyframe( 2, duration: 0.15)
                }
            }
    }
}
