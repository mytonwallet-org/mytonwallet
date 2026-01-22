
import SwiftUI
import UIKit
import WalletContext
import Perception

struct SegmentedControlItemView: View {
    
    let model: SegmentedControlModel
    var item: SegmentedControlItem
    
    var body: some View {
        WithPerceptionTracking {
            _SegmentedControlItemView(
                selectedItemId: model.selectedItem?.id,
                distanceToItem: model.distanceToItem(itemId: item.id),
                item: item,
            )
            .contentShape(.capsule)
            .simultaneousGesture(TapGesture().onEnded {
                model.onSelect(item)
            }, isEnabled: model.selectedItem?.id != item.id)
        }
    }
}

struct _SegmentedControlItemView: View {

    var selectedItemId: String?
    var distanceToItem: CGFloat
    var item: SegmentedControlItem
    
    var isSelected: Bool { selectedItemId == item.id }
    
    var body: some View {
        content
            .fixedSize()
            .padding(.horizontal, SegmentedControlConstants.innerPadding)
            .padding(.vertical, 4.333)
    }
    
    var content: some View {
        HStack(spacing: 0) {
            Text(item.title)
            if item.menuContext != nil, !item.hidesMenuIcon {
                _SegmentedControlItemAccessory(distanceToItem: distanceToItem)
            }
        }
        .menuSource(isTapGestureEnabled: isSelected, menuContext: item.menuContext)
    }
}

struct _SegmentedControlItemAccessory: View {
    
    var distanceToItem: CGFloat
    
    var body: some View {
        Image.airBundle("SegmentedControlArrow")
            .opacity(0.5)
            .offset(x: 4)
            .scaleEffect(1 - distanceToItem)
            .frame(width: SegmentedControlConstants.accessoryWidth * (1 - distanceToItem), alignment: .leading)
    }
}
