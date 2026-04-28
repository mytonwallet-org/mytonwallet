import Foundation

@MainActor
public protocol NftAnimationPlaybackControlling: AnyObject {
    func setNftAnimationPlaybackActive(_ isActive: Bool)
}
