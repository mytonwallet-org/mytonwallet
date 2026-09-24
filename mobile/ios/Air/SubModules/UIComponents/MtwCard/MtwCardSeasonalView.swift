import CoreImage
import UIKit
import WalletContext
import WalletCore

public final class MtwCardSeasonalView: UIControl {
    public var onDisable: (() -> Void)?
    private let artwork = UIImageView()
    private let particleContainer = UIView()
    private let blurredArtwork = UIImageView()
    private let blurredParticles = UIImageView()
    private static let blurContext = CIContext()
    private var artworkRaster: UIImage?
    private var rasterSize = CGSize.zero
    private var theme: ApiUpdate.UpdateConfig.SeasonalTheme?
    private var bulbs: [UIImageView] = []
    private var isOn = false
    private var isAnimating = false
    private var sequence: Task<Void, Never>?
    private var displayLink: CADisplayLink?
    private var started: CFTimeInterval = 0
    private var particles: [Particle] = []
    private static let bulbPositions: [(CGFloat, CGFloat, UInt32)] = [
        (8, 27, 0xFFFFAE), (43, 34, 0xFFB3B3), (74, 34, 0xFEFB0D), (102, 32, 0x0AFFF6),
        (129, 20, 0xEDA3FF), (150, 32, 0xFEFB0D), (179, 35, 0xFFFFAE), (206, 37, 0xFFB3B3),
        (232, 31, 0x0AFFF6), (254, 21, 0xEDA3FF), (280, 32, 0xFEFB0D), (310, 38, 0xFFB3B3),
        (342, 36, 0xEDA3FF), (370, 26, 0xFFFFAE),
    ]
    private static let glow: UIImage = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 92, height: 92)).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 30, y: 30, width: 32, height: 32))
        }
        let input = CIImage(cgImage: image.cgImage!)
        let output = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10 * image.scale])
        let cgImage = CIContext().createCGImage(output, from: input.extent)!
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up).withRenderingMode(.alwaysTemplate)
    }()

    public init() {
        super.init(frame: .zero)
        artwork.contentMode = .scaleAspectFit
        isHidden = true
        addSubview(artwork)
        addSubview(blurredArtwork)
        addSubview(particleContainer)
        addSubview(blurredParticles)
        for view in [artwork, blurredArtwork, particleContainer, blurredParticles] {
            view.isUserInteractionEnabled = false
        }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addInteraction(UIContextMenuInteraction(delegate: self))
        accessibilityElementsHidden = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(theme: ApiUpdate.UpdateConfig.SeasonalTheme?) {
        isHidden = theme == nil
        guard self.theme != theme else { return }
        prepareForReuse()
        self.theme = theme
        isHidden = theme == nil
        switch theme {
        case .newYear:
            artwork.image = .airBundle("NewYearGarland")
            bulbs = Self.bulbPositions.map { _, _, hex in
                let view = UIImageView(image: Self.glow)
                view.tintColor = UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                                        green: CGFloat((hex >> 8) & 255) / 255,
                                        blue: CGFloat(hex & 255) / 255, alpha: 1)
                view.alpha = 0
                addSubview(view)
                return view
            }
            if window != nil { animateBulbs(turnOn: true) }
        case .valentine:
            artwork.image = .airBundle("ValentinesHearts")
        case nil:
            artwork.image = nil
        }
        setNeedsLayout()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            sequence?.cancel()
            sequence = nil
            finishParticles()
            isAnimating = false
        } else if theme == .newYear, !isOn {
            animateBulbs(turnOn: true)
        }
    }

    public func prepareForReuse() {
        sequence?.cancel()
        sequence = nil
        finishParticles()
        bulbs.forEach { $0.removeFromSuperview() }
        bulbs = []
        isOn = false
        isAnimating = false
        theme = nil
        artwork.image = nil
        artworkRaster = nil
        isHidden = true
    }

    @objc private func tapped() {
        guard !isAnimating else { return }
        switch theme {
        case .newYear: animateBulbs(turnOn: !isOn)
        case .valentine: startParticles()
        case nil: break
        }
    }

    private func animateBulbs(turnOn: Bool) {
        sequence?.cancel()
        isAnimating = true
        if !AppStorageHelper.animations || UIAccessibility.isReduceMotionEnabled {
            bulbs.forEach { $0.alpha = turnOn ? 0.6 : 0 }
            isOn = turnOn
            isAnimating = false
            return
        }
        sequence = Task { [weak self] in
            guard let self else { return }
            let indices = turnOn ? Array(bulbs.indices) : Array(bulbs.indices.reversed())
            for index in indices {
                guard !Task.isCancelled, bulbs.indices.contains(index) else { return }
                UIView.animate(withDuration: 0.01, delay: 0, options: .curveLinear) {
                    self.bulbs[index].alpha = turnOn ? 0.6 : 0
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            isOn = turnOn
            isAnimating = false
        }
    }

    private struct Particle {
        let view: UIImageView
        let heart: Bool
        let x = CGFloat.random(in: 0.06...0.94)
        let y = CGFloat.random(in: 0.14...0.86)
        let scale = CGFloat.random(in: 0.5...1.1)
        let rotation = Double.random(in: -10...10)
        let driftX = CGFloat.random(in: -0.06...0.06)
        let driftY = CGFloat.random(in: -0.35...0.12)
        let wiggleX = CGFloat.random(in: 0.008...0.024)
        let wiggleY = CGFloat.random(in: 0.02...0.06)
        let wiggleRotation = Double.random(in: 2...8)
        let speed = Double.random(in: 1.2...2.2)
        let phase = Double.random(in: 0...(Double.pi * 2))
    }

    private func startParticles() {
        guard AppStorageHelper.animations, !UIAccessibility.isReduceMotionEnabled else { return }
        isAnimating = true
        for heart in [true, false] {
            for _ in 0..<Int.random(in: 8...12) {
                let view = UIImageView(image: .airBundle(heart ? "ValentinesHeart" : "ValentinesSparkle"))
                view.contentMode = .scaleAspectFit
                view.isUserInteractionEnabled = false
                particleContainer.addSubview(view)
                particles.append(Particle(view: view, heart: heart))
            }
        }
        started = CACurrentMediaTime()
        let target = SeasonalFrameTarget { [weak self] in self?.updateParticles() }
        let link = CADisplayLink(target: target, selector: #selector(SeasonalFrameTarget.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        updateParticles()
    }

    private func updateParticles() {
        let elapsed = CACurrentMediaTime() - started
        guard elapsed < 3.6 else { finishParticles(); return }
        let progress = min(1, elapsed / 3.2)
        let visibility = easeInOut(min(1, elapsed / 0.4)) * easeInOut(min(1, (3.6 - elapsed) / 0.4))
        for particle in particles {
            let phase = elapsed * particle.speed + particle.phase
            let scale = particle.scale * (1 + 0.05 * sin(phase * 1.5))
            let width = bounds.height * (particle.heart ? 0.52 : 0.36) * scale
            let imageSize = particle.view.image!.size
            particle.view.bounds.size = CGSize(width: width, height: width * imageSize.height / imageSize.width)
            particle.view.center = CGPoint(x: (particle.x + particle.driftX * progress + particle.wiggleX * sin(phase)) * bounds.width,
                                           y: (particle.y + particle.driftY * progress + particle.wiggleY * cos(phase * 1.2)) * bounds.height)
            particle.view.transform = CGAffineTransform(rotationAngle: (particle.rotation + particle.wiggleRotation * sin(phase * 1.1)) * .pi / 180)
            particle.view.alpha = 1
        }
        updateBlur(visibility: visibility)
    }

    // Match SwiftUI's easeInOut curve during the two 0.4 s blur swaps. Rendering
    // is confined to these swaps; the 3.2 s particle motion uses ordinary layers.
    private func easeInOut(_ x: Double) -> Double {
        var low = 0.0, high = 1.0
        for _ in 0..<14 {
            let t = (low + high) / 2, u = 1 - t
            let value = 3 * u * u * t * 0.42 + 3 * u * t * t * 0.58 + t * t * t
            if value < x { low = t } else { high = t }
        }
        let t = (low + high) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }

    private func updateBlur(visibility: CGFloat) {
        let padding: CGFloat = 24
        let paddedBounds = bounds.insetBy(dx: -padding, dy: -padding)
        blurredArtwork.frame = paddedBounds
        blurredParticles.frame = paddedBounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = traitCollection.displayScale
        let renderer = UIGraphicsImageRenderer(size: paddedBounds.size, format: format)
        if artworkRaster == nil || rasterSize != bounds.size {
            rasterSize = bounds.size
            artworkRaster = renderer.image { context in
                context.cgContext.translateBy(x: padding, y: padding)
                artwork.image?.draw(in: artwork.frame)
            }
        }
        func blurred(_ image: UIImage, radius: CGFloat) -> UIImage? {
            guard let source = image.cgImage else { return nil }
            let input = CIImage(cgImage: source)
            let output = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * image.scale])
            guard let result = Self.blurContext.createCGImage(output, from: input.extent) else { return nil }
            return UIImage(cgImage: result, scale: image.scale, orientation: .up)
        }
        artwork.isHidden = true
        blurredArtwork.alpha = 1 - visibility
        if visibility < 0.999, let artworkRaster {
            blurredArtwork.image = blurred(artworkRaster, radius: 8 * visibility)
        }
        particleContainer.isHidden = false
        particleContainer.alpha = 1
        if visibility < 0.999 {
            let raster = renderer.image { context in
                context.cgContext.translateBy(x: padding, y: padding)
                particleContainer.layer.render(in: context.cgContext)
            }
            blurredParticles.image = blurred(raster, radius: 8 * (1 - visibility))
            blurredParticles.alpha = visibility
            particleContainer.isHidden = true
        } else {
            blurredParticles.image = nil
        }
    }

    private func finishParticles() {
        displayLink?.invalidate()
        displayLink = nil
        particles.forEach { $0.view.removeFromSuperview() }
        particles = []
        artwork.alpha = 1
        artwork.isHidden = false
        blurredArtwork.image = nil
        blurredParticles.image = nil
        particleContainer.isHidden = false
        isAnimating = false
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let imageSize = artwork.image?.size ?? bounds.size
        artwork.frame = CGRect(x: 0, y: 0, width: bounds.width,
                               height: bounds.width * imageSize.height / max(1, imageSize.width))
        particleContainer.frame = bounds
        let scale = bounds.width / 378
        for (index, bulb) in bulbs.enumerated() {
            let point = Self.bulbPositions[index]
            bulb.bounds.size = CGSize(width: 92 * scale, height: 92 * scale)
            let x = point.0 * scale
            bulb.center = CGPoint(x: effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.width - x : x, y: point.1 * scale)
        }
        if !particles.isEmpty { updateParticles() }
    }

    public override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard theme != nil else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [UIAction(title: lang("Disable Seasonal Theming"), image: UIImage(systemName: "eye.slash")) { _ in self?.onDisable?() }])
        })
    }

    deinit { displayLink?.invalidate() }
}

private final class SeasonalFrameTarget: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func tick() { action() }
}
