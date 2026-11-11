import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

@Perceptible @MainActor
final class ReceiveHeaderTransitionModel {
    struct Selection {
        let source: String
        let destination: String
        let fraction: CGFloat

        func distance(to id: String) -> CGFloat? {
            if source == destination { return id == source ? 0 : nil }
            if id == source { return -fraction }
            if id == destination { return 1 - fraction }
            return nil
        }
    }

    var selection: Selection?

    func settle(on id: String) {
        selection = .init(source: id, destination: id, fraction: 0)
    }
}

struct ReceiveHeaderView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    
    var viewModel: SegmentedControlModel
    var accountContext: AccountContext
    var transition: ReceiveHeaderTransitionModel? = nil
    var availableHeight: CGFloat = headerHeight
        
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                ZStack {
                    // The background is visible for extra-scrolling (out of [0...1] progress) state.
                    // Should be a "dark" color to prevent navigation controls "thin glass" (non-whitish) appearance loosing
                    Color.black.opacity(0.51)
                    
                    ForEach(visibleItems) { item in
                        WithPerceptionTracking {
                            let distance = abs(distance(to: item.id))
                            receiveBackground(for: item.id)
                                .opacity(1 - distance)
                        }
                    }
                }
                
                ZStack {
                    // Keep QR views alive so network selection does not render codes during the transition
                    ForEach(viewModel.items) { item in
                        WithPerceptionTracking {
                            if let chain = ApiChain(rawValue: item.id) {
                                let isVisible = transition == nil || transition?.selection?.distance(to: item.id) != nil
                                ReceiveHeaderItemView(
                                    progress: (isVisible ? distance(to: item.id) : 1) * (layoutDirection == .rightToLeft ? -1 : 1),
                                    chain: chain,
                                    address: accountContext.account.getAddress(chain: chain) ?? ""
                                )
                                .opacity(isVisible ? 1 : 0)
                                .allowsHitTesting(isVisible)
                                .accessibilityHidden(!isVisible)
                            }
                        }
                    }
                }
                .scaleEffect(min(1, max(0, availableHeight - 96) / 220))
                .padding(.top, 48)
            }
        }
    }

    private var visibleItems: [SegmentedControlItem] {
        guard let transition else { return viewModel.items }
        return viewModel.items.filter { transition.selection?.distance(to: $0.id) != nil }
    }

    private func distance(to id: String) -> CGFloat {
        transition?.selection?.distance(to: id) ?? viewModel.directionalDistanceToItem(itemId: id)
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
    
    var progress: CGFloat
    var chain: ApiChain
    var address: String

    var body: some View {
        WithPerceptionTracking {
            let progressAbs = 1 - abs(progress)
            
            ZStack {
                receiveOrnament(progressAbs: progressAbs)
                
                if IS_GRAM_WALLET && chain == .ton && TelegramDiamondView.isAvailable {
                    TelegramReceiveQRCodeView(address: address, renderingEnabled: progressAbs > 0.99)
                        .id(address)
                        .frame(width: 220, height: 220)
                        .clipShape(.rect(cornerRadius: 32))
                        .opacity(interpolate(from: 0.25, to: 1, progress: progressAbs))
                } else {
                    _QRCodeView(chain: chain, address: address, opacity: interpolate(from: 0.25, to: 1, progress: progressAbs), onTap: {})
                        .id(address)
                        .frame(width: 220, height: 220)
                        .clipShape(.rect(cornerRadius: 32))
                }
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
