//
//  PaletteSection.swift
//  MyTonWalletAir
//
//  Created by nikstar on 17.10.2025.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Flow
import Perception
import Dependencies

private let _horizontalPadding = 16.0
private let _fallbackHorizontalPadding = 14.5
private let itemSize = 30.0
private let minimumSpacing = 16.0

@Perceptible
final class PaletteSettingsViewModel {
    
    var accountId: String {
        didSet {
            if accountId != oldValue {
                startLoadTask()
            }
        }
    }
    
    var currentColorId: Int?
    var availableColorIds: Set<Int?> = [nil]
    var isLoading: Bool = true
    
    @PerceptionIgnored
    @Dependency(\.accountStore) var accountStore
    @PerceptionIgnored
    @Dependency(\.accountSettings) var _accountSettings

    @PerceptionIgnored
    var nftsByColorIndex: [Int: [ApiNft]] = [:]
    
    @PerceptionIgnored
    var loadTask: Task<Void, any Error>?
    
    init(accountId: String) {
        self.accountId = accountId
        startLoadTask()
    }
    
    var accountSettings: AccountSettings {
        _accountSettings.for(accountId: accountId)
    }
    
    func setColorId(_ id: Int?) {
        withAnimation {
            if id == currentColorId {
                return
            } else if id == nil {
                accountSettings.setAccentColorNft(nil)
            } else {
                let id = id!
                if let nft = nftsByColorIndex[id]?.first {
                    accountSettings.setAccentColorNft(nft)
                }
            }
            self.currentColorId = id
        }
    }
    
    func startLoadTask() {
        let currentColorIndex = accountSettings.accentColorIndex
        self.currentColorId = currentColorIndex
        availableColorIds = [nil, currentColorIndex]
        
        loadTask?.cancel()
        loadTask = Task {
            let nfts = NftStore.getAccountMtwCards(accountId: accountId)
            let nftsByColorIndex = await getAccentColorsFromNfts(nftAddresses: Array(nfts.keys), nftsByAddress: nfts)
            try Task.checkCancellation()
            self.nftsByColorIndex = nftsByColorIndex
            await MainActor.run {
                withAnimation {
                    isLoading = false
                    availableColorIds = Set<Int?>(nftsByColorIndex.keys.map { $0 } + [nil])
                }
            }
        }
    }
}


struct PaletteSection: View {
    
    let viewModel: PaletteSettingsViewModel
    @State private var angle: Angle = .zero
    @State private var containerWidth = 0.0
    
    var body: some View {
        WithPerceptionTracking {
            InsetSection {
                cell
            } header: {
                Text(lang("Palette"))
            } footer: {
                Text(lang("Get a unique MyTonWallet Card to unlock new palettes."))
            }
        }
    }
    
    var cell: some View {
        InsetCell(horizontalPadding: resolvedHorizontalPadding, verticalPadding: 16) {
            HStack {
                PaletteGrid(viewModel: viewModel, availableColorIds: viewModel.availableColorIds, spacing: spacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(!viewModel.isLoading)
                    .opacity(viewModel.isLoading ? 0.4 : 1)
                    .transition(.opacity)
                    .id(viewModel.availableColorIds)
            }
            .overlay {
                if viewModel.isLoading {
                    Image.airBundle("ActivityIndicator")
                        .renderingMode(.template)
                        .rotationEffect(angle)
                        .onAppear {
                            withAnimation(.linear(duration: 0.625).repeatForever(autoreverses: false)) {
                                angle += .radians(2 * .pi)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { containerWidth = $0 }
    }
    
    var resolvedHorizontalPadding: CGFloat {
        if containerWidth == 0 {
            return _horizontalPadding
        }
        let width = containerWidth - 2 * _horizontalPadding
        let n = floor((width + minimumSpacing) / (itemSize + minimumSpacing))
        let spacing = (width - itemSize * n) / (n - 1)
        if spacing > 24.0 {
            return _fallbackHorizontalPadding
        } else {
            return _horizontalPadding
        }
    }
    
    var spacing: CGFloat {
        if containerWidth == 0 {
            return minimumSpacing
        }
        let width = containerWidth - 2 * resolvedHorizontalPadding
        let n = floor((width + minimumSpacing) / (itemSize + minimumSpacing))
        let spacing = (width - itemSize * n) / (n - 1)
        return spacing
    }
}

struct PaletteGrid: View {
    
    let viewModel: PaletteSettingsViewModel
    var availableColorIds: Set<Int?>
    var spacing: CGFloat
    
    var unlockedColors: [PaletteColor] {
        PaletteColor.all.filter { availableColorIds.contains($0.id) }
    }
    var lockedColors: [PaletteColor] {
        PaletteColor.all.filter { !availableColorIds.contains($0.id) }
    }
    
    var body: some View {
        WithPerceptionTracking {
            HFlow(alignment: .center, itemSpacing: spacing, rowSpacing: 16, justified: false, distributeItemsEvenly: false) {
                unlockedColorsView
                lockedColorsView
            }
        }
    }
    
    var unlockedColorsView: some View {
        ForEach(unlockedColors) { color in
            WithPerceptionTracking {
                PaletteItemView(
                    paletteColor: color,
                    state: color.id == viewModel.currentColorId && !viewModel.isLoading ? .current : .available,
                    onTap: { source in
                        if color.id != viewModel.currentColorId {
                            showSwoopView(color: color.color, source: source)
                        }
                        viewModel.setColorId(color.id)
                    },
                )
            }
        }
    }
    
    var lockedColorsView: some View {
        ForEach(lockedColors) { color in
            WithPerceptionTracking {
                PaletteItemView(
                    paletteColor: color,
                    state: .locked,
                    onTap: { _ in
                        AppActions.showToast(
                            message: lang("Get a unique MyTonWallet Card to unlock new palettes."),
                            tapAction: AppActions.showUpgradeCard
                        )
                        Haptics.play(.lightTap)
                    },
                )
            }
        }
    }
}

struct PaletteColor: Identifiable, Equatable, Hashable {
    var id: Optional<Int>
    var color: Color
    
    static let all: [PaletteColor] = [
        PaletteColor(id: nil, color: .airBundle("TC1_PrimaryColor"))
    ] + ACCENT_COLORS.enumerated().map { id, color in
        PaletteColor(id: id, color: Color(color) )
    }
}

enum PaletteItemState: CaseIterable {
    case current
    case available
    case locked
}

struct PaletteItemView: View {
    
    var paletteColor: PaletteColor
    var state: PaletteItemState
    var onTap: (CGPoint) -> ()
    
    var color: Color { paletteColor.color }
    
    @State private var center: CGPoint = .zero
    
    var body: some View {
        Circle()
            .fill(color)
            .overlay {
                if state == .current {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.air.groupedItem, lineWidth: 2)
                        Circle()
                            .strokeBorder(color, lineWidth: 2)
                            .padding(-2)
                    }
                }
            }
            .overlay {
                if state == .locked {
                    Image.airBundle("PaletteLock")
                        .foregroundStyle(lockColor.opacity(0.5))
                }
            }
            .onTapGesture(perform: _onTap)
            .frame(width: itemSize, height: itemSize)
            .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .global).center }, action: { center = $0 })
    }
    
    var lockColor: Color {
        if paletteColor.id == ACCENT_BNW_INDEX {
            return Color.air.groupedItem
        }
        return .white
    }
    
    func _onTap() {
        onTap(center)
    }
}

@MainActor func showSwoopView(color: Color, source: CGPoint) {
    guard let window = topViewController()?.view.window else { return }
    let view = HostingView {
        SwoopView(color: color, center: source)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    window.addSubview(view)
    view.frame = window.bounds
    NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: window.topAnchor),
        view.bottomAnchor.constraint(equalTo: window.bottomAnchor),
        view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
    ])
    view.isUserInteractionEnabled = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        view.removeFromSuperview()
    }
}

struct SwoopView: View {
    
    var color: Color
    var center: CGPoint
    
    @State private var outerRadius = 30.0
    @State private var innerRadius = 0.0
    @State private var opacity = 1.0
    @State private var blur = 0.0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: outerRadius, height: outerRadius)
            Circle()
                .fill(Color.black)
                .frame(width: innerRadius, height: innerRadius)
                .blendMode(.destinationOut)
        }
        .frame(width: outerRadius, height: outerRadius)
        .compositingGroup()
        .blur(radius: blur)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.7)) {
                outerRadius = 2000
//                innerRadius = 1000
                opacity = 0
                blur = 220
            }
        }
        .position(center)
        .ignoresSafeArea()
    }
}
