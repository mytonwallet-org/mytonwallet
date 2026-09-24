import Foundation

@MainActor @objc
protocol WalletAssetsEmptyStateAnimationControlling: AnyObject {
    func setWalletAssetsEmptyStateAnimationActive(_ isActive: Bool)
}
