//
//  TonConnectOverlayView.swift
//  UIDapp
//
//  Created by nikstar on 30.10.2025.
//

import UIKit
import SwiftUI
import UIComponents
import WalletContext
import Perception

let CLOSE_BUTTON_DELAY = Duration.seconds(7)

final class TonConnectOverlayView: HostingView {
    
    private let viewModel = _TonConnectOverlayViewModel()
    
    init() {
        super.init(ignoreSafeArea: true) { [viewModel] in 
            _TonConnectOverlayView(viewModel: viewModel)
        }
        viewModel.view = self
    }
    
    func dismissSelf() {
        viewModel.dismissSelf()
    }
}

@Perceptible
final class _TonConnectOverlayViewModel {
    @PerceptionIgnored
    weak var view: TonConnectOverlayView?
    var isDismissing = false
    
    func dismissSelf() {
        withAnimation(.smooth(duration: 0.2)) {
            isDismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.view?.removeFromSuperview()
        }
    }
}

struct _TonConnectOverlayView: View {
    
    var viewModel: _TonConnectOverlayViewModel
    
    @State private var isShown = false
    @State private var closeShown = false
    @State private var angle: Angle = .zero
    
    var body: some View {
        WithPerceptionTracking {
            Color.clear
            .overlay {
                if isShown {
                    ZStack {
                        Rectangle().fill(Material.thin)
                        Image.airBundle("ActivityIndicator")
                            .renderingMode(.template)
                            .rotationEffect(angle)
                            .onAppear {
                                withAnimation(.linear(duration: 0.625).repeatForever(autoreverses: false)) {
                                    angle += .radians(2 * .pi)
                                }
                            }
                            .foregroundStyle(Color.air.secondaryLabel)
                        
                        if closeShown {
                            Button(action: { viewModel.dismissSelf() }) {
                                Text(lang("Close"))
                            }
                            .buttonStyle(.airClearBackground)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 80)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .transition(.opacity)
                        }
                    }
                    .opacity(viewModel.isDismissing ? 0 : 1)
                    .transition(.opacity)
                }
            }
        
            .task {
                try? await Task.sleep(for: .seconds(0.25))
                withAnimation(.smooth(duration: 0.35)) {
                    isShown = true
                }
            }
            .task {
                try? await Task.sleep(for: CLOSE_BUTTON_DELAY)
                withAnimation(.smooth(duration: 0.3)) {
                    closeShown = true
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                viewModel.dismissSelf()
            }
        }
    }
}
