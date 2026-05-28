//
//  WalletSettingsGridCell.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.11.2025.
//

import UIKit
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import Kingfisher
import Lottie

struct WalletSettingsEmptyCell: View {
    
    var filter: WalletFilter
    let viewModel: WalletSettingsViewModel
    
    @State private var playTrigger = 0
    
    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                WUIAnimatedSticker("duck_no-data", size: 100, loop: false, playTrigger: playTrigger)
                VStack(spacing: 20) {
                    Text(filter.emptyTitle)
                        .font(.system(size: 17, weight: .semibold))
                    Text(filter.emptySubtitle)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .offset(y: -16)
            .onChange(of: viewModel.segmentedControllerDidSwitchTrigger) { _ in
                if viewModel.currentFilter == filter {
                    playTrigger += 1
                }
            }
        }
    }
}
