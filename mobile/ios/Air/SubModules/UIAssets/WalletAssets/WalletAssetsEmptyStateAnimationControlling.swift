import Foundation

@MainActor
protocol WalletAssetsEmptyStateAnimationControlling: AnyObject {
    func setWalletAssetsEmptyStateAnimationActive(_ isActive: Bool)
}
