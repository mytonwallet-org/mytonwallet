//
//  CollapsedContent.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import SwiftUIIntrospect
import Perception
import Dependencies

struct HomeHeaderCollapsedContent: View {
    
    let viewModel: AccountViewModel
    var topSafeAreaInset: CGFloat
    var collapsedHeight: CGFloat
    let isCollapsed: Bool
    var ns: Namespace.ID
    @State private var progress: CGFloat = 0
    
    var spacing: CGFloat { interpolate(from: 5, to: -2, progress: progress) }
    var balanceScale: CGFloat { interpolate(from: 1, to: 17.0/40.0, progress: progress) }
    var subtitleScale: CGFloat { interpolate(from: 1, to: 13.0/17.0, progress: progress) }
    var bottomPadding: CGFloat { interpolate(from: 20, to: targetBottomPadding, progress: progress) }
    
    var adjstedTopInset: CGFloat {
        topSafeAreaInset - (IOS_26_MODE_ENABLED ? 16 : 8)
    }
    var targetBottomPadding: CGFloat {
        IOS_26_MODE_ENABLED ? -3 : -10
    }
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: spacing) {
                MtwCardBalanceView(balance: viewModel.balance, style: .homeCollaped)
//                    .matchedGeometryEffect(
//                        id: "\(viewModel.accountId)-balance",
//                        in: ns,
//                        properties: .size,
//                        anchor: .center,
//                        isSource: isCollapsed
//                    )
                    .scaleEffect(balanceScale, anchor: .bottom)
                Text(viewModel.account.displayName)
                    .foregroundStyle(.secondary)
                    .scaleEffect(subtitleScale, anchor: .top)
                    .lineLimit(1)
            }
            .backportGeometryGroup()
            .scaleEffect(isCollapsed ? 1 : 56/40)
            .offset(x: !isCollapsed ? -12 : 0, y: !isCollapsed ? -64 : 0)
            .padding(.horizontal, 80)
            .padding(.bottom, bottomPadding)
            .onGeometryChange(for: CGFloat.self) { geom in
                let p = (geom.frame(in: .global).maxY - adjstedTopInset) / collapsedHeight
                return 1 - clamp(p, to: 0...1)
            } action: { newValue in
                self.progress = newValue
            }
            .opacity(isCollapsed ? 1 : 0)
        }
    }
}
