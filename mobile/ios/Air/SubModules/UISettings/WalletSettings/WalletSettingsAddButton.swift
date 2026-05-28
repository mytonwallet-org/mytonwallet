//
//  WalletSettingsVC.swift
//  UISettings
//
//  Created by nikstar on 02.11.2025.
//

import UIKit
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

struct WalletSettingsAddButton: View {
    
    let viewModel: WalletSettingsViewModel
    
    var body: some View {
        WithPerceptionTracking {
            if !viewModel.isReordering {
                ZStack {
                    LinearGradient(
                        colors: [Color.clear, Color.air.sheetBackground.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                    .padding(.top, -16)
                    .ignoresSafeArea()
                    
                    Button(action: onAdd) {
                        Label {
                            Text(viewModel.currentFilter.addTitle)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .buttonStyle(.airPrimary)
                    .padding(.horizontal, 30)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .animation(.smooth(duration: 0.2), value: viewModel.currentFilter)
                }
            }
        }
    }
    
    func onAdd() {
        viewModel.currentFilter.performAddAction()
    }
}
