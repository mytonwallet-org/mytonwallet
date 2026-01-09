import SwiftUI
import UIKit
import WalletCore
import WalletContext
import Kingfisher

public struct WUIIconViewToken: UIViewRepresentable {
    
    public var token: ApiToken?
    public var isStaking: Bool
    public var isWalletView: Bool
    public var showldShowChain: Bool
    public var size: CGFloat
    public var chainSize: CGFloat
    public var chainBorderWidth: CGFloat
    public var chainBorderColor: UIColor
    public var chainHorizontalOffset: CGFloat
    public var chainVerticalOffset: CGFloat
    
    public init(token: ApiToken? = nil, isStaking: Bool = false, isWalletView: Bool, showldShowChain: Bool, size: CGFloat, chainSize: CGFloat, chainBorderWidth: CGFloat, chainBorderColor: UIColor, chainHorizontalOffset: CGFloat, chainVerticalOffset: CGFloat) {
        self.token = token
        self.isStaking = isStaking
        self.isWalletView = isWalletView
        self.showldShowChain = showldShowChain
        self.size = size
        self.chainSize = chainSize
        self.chainBorderWidth = chainBorderWidth
        self.chainBorderColor = chainBorderColor
        self.chainHorizontalOffset = chainHorizontalOffset
        self.chainVerticalOffset = chainVerticalOffset
    }
    
    public func makeUIView(context: Context) -> IconView {
        let uiView = IconView(size: size)
        NSLayoutConstraint.activate([
            uiView.heightAnchor.constraint(equalToConstant: size),
            uiView.widthAnchor.constraint(equalToConstant: size)
        ])
        uiView.setChainSize(chainSize, borderWidth: chainBorderWidth, borderColor: chainBorderColor, horizontalOffset: chainHorizontalOffset, verticalOffset: chainVerticalOffset)
        uiView.config(with: token, isStaking: isStaking, isWalletView: isWalletView, shouldShowChain: showldShowChain)
        uiView.imageView.layer.cornerRadius = size/2
        return uiView
    }
    
    public func updateUIView(_ uiView: UIViewType, context: Context) {
        uiView.setChainSize(chainSize, borderWidth: chainBorderWidth, borderColor: chainBorderColor, horizontalOffset: chainHorizontalOffset, verticalOffset: chainVerticalOffset)
        uiView.config(with: token, isStaking: isStaking, isWalletView: isWalletView, shouldShowChain: showldShowChain)
    }
}

