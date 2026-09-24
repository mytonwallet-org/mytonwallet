import SwiftUI
import UIKit

/// The Lab timeline and SwiftUI previews use the same layered shader as HomeCard.
public struct CardBackgroundMotionFrame: UIViewRepresentable {
    private let seed: CardBackgroundSeed
    private let time: Double
    private let strength: Double
    private let showContrast: Bool
    private let blobMotion: CardBlobMotion

    public init(seed: CardBackgroundSeed, time: Double, strength: Double = CardBackgroundMotion.defaultStrength,
                showContrast: Bool = true, blobMotion: CardBlobMotion = .cardCenter) {
        self.seed = seed
        self.time = time
        self.strength = strength
        self.showContrast = showContrast
        self.blobMotion = blobMotion
    }

    public func makeUIView(context: Context) -> UIView { FrameView() }

    public func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? FrameView)?.update(seed: seed, time: time, strength: strength, showContrast: showContrast, blobMotion: blobMotion)
    }
}

private final class FrameView: UIView {
    private let fallback = UIImageView()
    private var metal: CardBackgroundMetalView?
    private var key: String?
    private var time = 0.0
    private var strength = 0.0
    private var blobMotion = CardBlobMotion.cardCenter

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        addSubview(fallback)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(seed: CardBackgroundSeed, time: Double, strength: Double, showContrast: Bool, blobMotion: CardBlobMotion) {
        self.time = time
        self.strength = strength
        self.blobMotion = blobMotion
        let key = "\(seed.cardId):\(seed.motionSeed):\(showContrast)"
        if self.key != key {
            self.key = key
            metal?.removeFromSuperview()
            metal = nil
            fallback.image = try? CardBackgroundRenderer.shared.image(seed: seed, showContrast: showContrast)
            if #available(iOS 17, *), let image = fallback.image,
               let renderer = CardBackgroundMetalView(image: image, seed: seed, showContrast: showContrast) {
                metal = renderer
                renderer.frame = bounds
                addSubview(renderer)
            }
        }
        metal?.showFrame(time: time, strength: strength, blobMotion: blobMotion)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fallback.frame = bounds
        metal?.frame = bounds
        metal?.showFrame(time: time, strength: strength, blobMotion: blobMotion)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { metal?.showFrame(time: time, strength: strength, blobMotion: blobMotion) }
    }
}
