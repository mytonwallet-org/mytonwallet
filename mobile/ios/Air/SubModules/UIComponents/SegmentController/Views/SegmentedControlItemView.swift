
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
                DispatchQueue.main.async {
                    if item.menuContext?.menuTriggered != true, model.selectedItem?.id != item.id {
                        model.onSelect(item)
                    }
                }
            }, isEnabled: true)
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
        .menuSource(
            isTapGestureEnabled: isSelected,
            menuContext: item.menuContext,
            edgeInsets: .init(top: -6, left: -SegmentedControlConstants.innerPadding, bottom: -6, right: -SegmentedControlConstants.innerPadding)
        )
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
