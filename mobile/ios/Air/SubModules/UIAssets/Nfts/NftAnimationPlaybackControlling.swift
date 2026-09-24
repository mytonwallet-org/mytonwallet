import Foundation

@MainActor @objc
public protocol NftAnimationPlaybackControlling: AnyObject {
    func setNftAnimationPlaybackActive(_ isActive: Bool)
}
