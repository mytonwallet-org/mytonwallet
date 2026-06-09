//
//  WalletSettingsAddButton.swift
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
            if viewModel.isReordering {
                if viewModel.preferredLayout == .list {
                    ZStack {
                        fadeGradient
                        deleteButton
                    }
                }
            } else {
                ZStack {
                    fadeGradient
                    addButton
                }
            }
        }
    }
    
    private var fadeGradient: some View {
        LinearGradient(
            colors: [Color.clear, .air.sheetBackground.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
        .padding(.top, -16)
        .ignoresSafeArea()
    }

    private var deleteButton: some View {
        let count = viewModel.selectedAccountIds.count
        
        return Button(action: onDelete) {
                Text(lang("$remove_wallets", arg1: count))
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.airSecondaryDestructive.withLegacyShadow())
            .fixedSize()
            .disabled(count == 0)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .animation(.smooth(duration: 0.2), value: count)
    }

    private func onDelete() {
        viewModel.deleteSelectedWallets()
    }

    private var addButton: some View {
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
    
    private func onAdd() {
        viewModel.currentFilter.performAddAction()
    }
}
