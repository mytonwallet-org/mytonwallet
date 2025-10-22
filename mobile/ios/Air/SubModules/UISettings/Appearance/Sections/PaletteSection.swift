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

private let _horizontalPadding = 12.5
private let _fallbackHorizontalPadding = 14.5
private let itemSize = 30.0
private let minimumSpacing = 15.0

final class PaletteSettingsViewModel: ObservableObject {
    @Published var currentColorId: Int?
    @Published var availableColorIds: Set<Int?>
    @Published var isLoading: Bool = true
    
    var nftsByColorIndex: [Int: [ApiNft]] = [:]
    
    init() {
        let currentColorId = AccountStore.currentAccountAccentColorIndex
        self.currentColorId = currentColorId
        availableColorIds = [nil, currentColorId]
        
        Task {
            let nfts = NftStore.currentAccountNfts ?? [:]
            let nftsByColorIndex = await getAccentColorsFromNfts(nftAddresses: Array(nfts.keys), nftsByAddress: nfts.mapValues(\.nft))
            self.nftsByColorIndex = nftsByColorIndex
            await MainActor.run {
                withAnimation {
                    isLoading = false
                    availableColorIds = Set<Int?>(nftsByColorIndex.keys.map { $0 } + [nil])
                }
            }
        }
    }
    
    func setColorId(_ id: Int?) {
        withAnimation {
            if id == currentColorId {
                return
            } else if id == nil {
                AccountStore.currentAccountAccentColorNft = nil
            } else {
                let id = id!
                if let nft = nftsByColorIndex[id]?.first {
                    AccountStore.currentAccountAccentColorNft = nft
                }
            }
            self.currentColorId = id
        }
    }
}


struct PaletteSection: View {
    
    @StateObject var viewModel = PaletteSettingsViewModel()
    @State private var angle: Angle = .zero
    @State private var containerWidth = 0.0
    
    var body: some View {
        InsetCell(horizontalPadding: resolvedHorizontalPadding, verticalPadding: 12) {
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
        InsetButtonCell(action: onUnlockNew) {
            Text(lang("Unlock New Palettes"))
                .foregroundStyle(Color.accentColor)
        }
    }
    
    var resolvedHorizontalPadding: CGFloat {
        if containerWidth == 0 {
            return _horizontalPadding
        }
        let width = containerWidth - 2 * _horizontalPadding
        let n = floor((width + minimumSpacing) / (itemSize + minimumSpacing))
        let spacing = (width - itemSize * n) / (n - 1)
        if spacing > 20.0 {
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
    
    func onUnlockNew() {
        AppActions.showUpgradeCard()
    }
}

struct PaletteGrid: View {
    
    @ObservedObject var viewModel: PaletteSettingsViewModel
    var availableColorIds: Set<Int?>
    var spacing: CGFloat
    
    var unlockedColors: [PaletteColor] {
        PaletteColor.all.filter { availableColorIds.contains($0.id) }
    }
    var lockedColors: [PaletteColor] {
        PaletteColor.all.filter { !availableColorIds.contains($0.id) }
    }
    
    var body: some View {
        HFlow(alignment: .center, itemSpacing: spacing, rowSpacing: 12, justified: false, distributeItemsEvenly: false) {
            ForEach(unlockedColors) { color in
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
            ForEach(lockedColors) { color in
                PaletteItemView(
                    paletteColor: color,
                    state: .locked,
                    onTap: { _ in
                        topWViewController()?.showToast(
                            message: lang("Get a unique MyTonWallet Card to unlock new palettes."),
                            tapAction: AppActions.showUpgradeCard
                        )
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                        .foregroundStyle(Color.air.groupedItem.opacity(0.5))
                }
            }
            .onTapGesture(perform: _onTap)
            .frame(width: itemSize, height: itemSize)
            .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .global).center }, action: { center = $0 })
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
