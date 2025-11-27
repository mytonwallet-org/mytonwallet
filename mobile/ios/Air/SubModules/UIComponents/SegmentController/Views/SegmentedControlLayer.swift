//
//  SegmentedControlLayer.swift
//  MyTonWalletAir
//
//  Created by nikstar on 15.11.2025.
//

import SwiftUI
import UIKit
import WalletContext
import Perception


struct SegmentedControlLayer: View {
    
    let model: SegmentedControlModel
    var ns: Namespace.ID
    
    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: SegmentedControlConstants.spacing) {
                ForEach(model.items) { item in
                    SegmentedControlItemView(
                        model: model,
                        item: item,
                    )
                    .mask {
                        Capsule()
                            .matchedGeometryEffect(id: "capsule", in: ns, properties: .frame, anchor: .center, isSource: false)
                    }
                    .background(alignment: .leading) {
                        BackgroundItemView(model: model, item: item)
                    }
                }
            }
        }
    }
}

struct BackgroundItemView: View {
    
    let model: SegmentedControlModel
    var item: SegmentedControlItem
    
    var body: some View {
        Text(item.title)
            .padding(.horizontal, SegmentedControlConstants.innerPadding)
            .foregroundStyle(Color(model.secondaryColor))
            .onGeometryChange(
                for: CGSize.self,
                of: { $0.size },
                action: { size in
                    model.setSize(itemId: item.id, size: size)
                }
            )
    }
}
