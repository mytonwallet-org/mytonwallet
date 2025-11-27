//
//  WalletCardView.swift
//  UIHome
//
//  Created by Sina on 7/10/24.
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

private let log = Log("HomeHeader")


struct HomeHeader: View {
    
    let homeHeaderViewModel: HomeHeaderViewModel
    
    @Namespace private var ns
    
    var body: some View {
        WithPerceptionTracking {
            Color.clear.opacity(0.3)
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .bottom) {
                        Color.clear
                        HomeHeaderCollapsedContent(
                            viewModel: homeHeaderViewModel.currentAccountViewModel,
                            topSafeAreaInset: homeHeaderViewModel.topSafeAreaInset,
                            collapsedHeight: homeHeaderViewModel.collapsedHeight,
                            isCollapsed: homeHeaderViewModel.isCollapsed,
                            ns: ns,
                        )
                        .padding(.horizontal, 16)
                        AccountSelectorView(
                            viewModel: homeHeaderViewModel,
                            ns: ns,
                        )
                        .overlay {
                            SideGradient(homeHeaderViewModel: homeHeaderViewModel)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .onGeometryChange(for: Bool.self, of: { $0.frame(in: .global).maxY < 166 }, action: { homeHeaderViewModel.cardIsHidden = $0 })
        }
    }
}


struct SideGradient: View {
    
    let homeHeaderViewModel: HomeHeaderViewModel
    
    var body: some View {
        WithPerceptionTracking {
            if !homeHeaderViewModel.isCollapsed {
                ZStack {
                    LinearGradient(colors: [.air.groupedBackground.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LinearGradient(colors: [.air.groupedBackground.opacity(0.6), .clear], startPoint: .trailing, endPoint: .leading)
                        .frame(width: 16)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
