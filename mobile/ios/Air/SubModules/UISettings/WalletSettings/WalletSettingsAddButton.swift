//
//  WalletSettingsAddButton.swift
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

    @State private var animatedContent: BottomButtonContent

    private enum BottomButtonContent: Equatable {
        case hidden
        case add
        case delete
    }
    
    private var bottomButtonContent: BottomButtonContent {
        switch viewModel.mode {
        case .reordering:
            return .hidden
        case .select:
            return .delete
        case .normal:
            return viewModel.isDeletingAccounts ? .delete : .add
        }
    }

    init(viewModel: WalletSettingsViewModel) {
        self.viewModel = viewModel
        let initial: BottomButtonContent = {
            switch viewModel.mode {
            case .reordering: return .hidden
            case .select:     return .delete
            case .normal:     return viewModel.isDeletingAccounts ? .delete : .add
            }
        }()
        self._animatedContent = State(initialValue: initial)
    }
    
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                if animatedContent != .hidden {
                    fadeGradient
                        .transition(.opacity)
                }

                if animatedContent != .hidden {
                    Group {
                        switch animatedContent {
                        case .add:
                            addButton
                        default:
                            deleteButton
                        }
                    }
                    .id(animatedContent)
                    .transition(.move(edge: .bottom))
                }
            }
            .onChange(of: bottomButtonContent) { new in
                withAnimation(new != .hidden ? .spring(duration: 0.48, bounce: 0.18) : .smooth(duration: 0.28)) {
                    animatedContent = new
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
        let isDeleting = viewModel.isDeletingAccounts
        
        return Button(action: onDelete) {
            Text(lang("$remove_wallets", arg1: count))
                .padding(.horizontal, 20)
                .opacity(isDeleting ? 0 : 1)
                .overlay {
                    if isDeleting {
                        WUIActivityIndicator()
                    }
                }
        }
        .buttonStyle(.airSecondaryDestructive.withLegacyShadow())
        .fixedSize()
        .disabled(isDeleting || count == 0)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .animation(.smooth(duration: 0.2), value: count)
            .animation(.smooth(duration: 0.2), value: isDeleting)
    }

    private func onDelete() {
        guard !viewModel.isDeletingAccounts else { return }
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
