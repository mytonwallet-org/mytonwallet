import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

struct ReceiveHeaderView: View {
    
    var viewModel: SegmentedControlModel
    var accountContext: AccountContext
        
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                ZStack {
                    // The background is visible for extra-scrolling (out of [0...1] progress) state.
                    // Should be a "dark" color to prevent navigation controls "thin glass" (non-whitish) appearance loosing
                    Color.black.opacity(0.51)
                    
                    ForEach(viewModel.items) { item in
                        WithPerceptionTracking {
                            let distance = viewModel.distanceToItem(itemId: item.id)
                            receiveBackground(for: item.id)
                                .opacity(1 - distance)
                        }
                    }
                }
                
                ZStack {
                    ForEach(viewModel.items) { item in
                        WithPerceptionTracking {
                            if let chain = ApiChain(rawValue: item.id) {
                                ReceiveHeaderItemView(viewModel: viewModel, chain: chain, address: accountContext.account.getAddress(chain: chain) ?? "")
                            }
                        }
                    }
                }
                .padding(.top, 48)
            }
        }
    }

    @ViewBuilder
    private func receiveBackground(for itemId: String) -> some View {
        if let chain = ApiChain(rawValue: itemId) {
            ReceiveHeaderBackgroundView(chain: chain)
        } else {
            Color.black.opacity(0.51)
        }
    }
}

private struct ReceiveHeaderItemView: View {
    
    var viewModel: SegmentedControlModel
    var chain: ApiChain
    var address: String

    var body: some View {
        WithPerceptionTracking {
            let progress = viewModel.directionalDistanceToItem(itemId: chain.rawValue)
            let progressAbs = 1 - abs(progress)
            
            ZStack {
                receiveOrnament(progressAbs: progressAbs)
                
                _QRCodeView(chain: chain, address: address, opacity: interpolate(from: 0.25, to: 1, progress: progressAbs), onTap: {})
                    .frame(width: 220, height: 220)
                    .clipShape(.rect(cornerRadius: 32))
            }
            .scaleEffect(min(1.05, interpolate(from: 0.5, to: 1, progress: progressAbs)))
            .offset(x: progress * 320)
            .rotation3DEffect(.degrees(-10) * progress, axis: (0, 1, 0))
        }
    }

    @ViewBuilder
    private func receiveOrnament(progressAbs: CGFloat) -> some View {
        ReceiveHeaderOrnamentView(
            chain: chain,
            opacity: interpolate(from: 0.25, to: 1, progress: progressAbs)
        )
    }
}


private struct _QRCodeView: UIViewRepresentable {
        
    var chain: ApiChain
    var address: String
    var opacity: CGFloat
    let onTap: () -> ()
    
    final class Coordinator: QRCodeContainerViewDelegate {
        var onTap: () -> ()
        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }
        func qrCodePressed() {
            onTap()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .white
        let url = chain.config.formatTransferUrl?(address, nil, nil, nil) ?? address
        let view = QRCodeContainerView(url: url, image: chain.image, size: 200, centerImageSize: 40, delegate: context.coordinator)
        container.addSubview(view)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 220),
            container.heightAnchor.constraint(equalToConstant: 220),
            view.widthAnchor.constraint(equalToConstant: 200),
            view.heightAnchor.constraint(equalToConstant: 200),
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {
        uiView.alpha = self.opacity
    }
}
