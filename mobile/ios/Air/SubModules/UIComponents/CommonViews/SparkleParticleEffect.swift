import SwiftUI
import UIKit

private struct SparkleColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

private struct SparkleColorPair: Equatable {
    let from: SparkleColor
    let to: SparkleColor

    func resolve(rng: inout SeededRandom) -> UIColor {
        UIColor(
            red: rng.nextBetween(from.red, to.red),
            green: rng.nextBetween(from.green, to.green),
            blue: rng.nextBetween(from.blue, to.blue),
            alpha: 1
        )
    }
}

private let defaultSparkleGradient = SparkleColorPair(
    from: SparkleColor(red: 107.0 / 255.0, green: 147.0 / 255.0, blue: 1),
    to: SparkleColor(red: 228.0 / 255.0, green: 106.0 / 255.0, blue: 206.0 / 255.0)
)

private struct SparkleParticleConfig {
    var width: CGFloat = 350
    var height: CGFloat = 230
    var particleCount = 100
    var color: SparkleColorPair = defaultSparkleGradient
    var baseSize: CGFloat = 6
    var minSpawnRadius: CGFloat = 35
    var maxSpawnRadius: CGFloat = 70
    var distanceLimit: CGFloat = 0.7
    var fadeInTime: CGFloat = 0.25
    var fadeOutTime: CGFloat = 1
    var minLifetime: CGFloat = 4
    var maxLifetime: CGFloat = 6
    var maxStartTimeDelay: CGFloat = 3
    var edgeFadeZone: CGFloat = 50
    var centerShift: CGPoint = .zero
    var accelerationFactor: CGFloat = 3
    var selfDestroyTime: CGFloat = 0

    static func burst(color: SparkleColorPair, centerShift: CGPoint, canvasSize: CGSize) -> SparkleParticleConfig {
        var config = SparkleParticleConfig()
        config.width = canvasSize.width
        config.height = canvasSize.height
        config.particleCount = 5
        config.color = color
        config.minSpawnRadius = 5
        config.maxSpawnRadius = 50
        config.distanceLimit = 1
        config.fadeInTime = 0.05
        config.minLifetime = 3
        config.maxLifetime = 3
        config.maxStartTimeDelay = 0
        config.selfDestroyTime = 3
        config.centerShift = centerShift
        return config
    }
}

private struct SparkleParticle {
    let startPosition: CGPoint
    let velocity: CGPoint
    let startTime: CGFloat
    let lifetime: CGFloat
    let size: CGFloat
    let baseOpacity: CGFloat
    let color: UIColor
    let path: CGPath
}

private final class SparkleParticleSystem {
    let config: SparkleParticleConfig
    let startTime = CACurrentMediaTime()
    let center: CGPoint
    let avgDistance: CGFloat
    let particles: [SparkleParticle]

    init(config: SparkleParticleConfig) {
        self.config = config
        self.center = CGPoint(
            x: config.width / 2 + config.centerShift.x,
            y: config.height / 2 + config.centerShift.y
        )
        self.avgDistance = (config.width / 2 + config.height / 2) / 2

        var rng = SeededRandom(seed: Int.random(in: 0..<1_000_000))
        var particles: [SparkleParticle] = []
        particles.reserveCapacity(config.particleCount)

        for _ in 0..<config.particleCount {
            let angle = rng.next() * .pi * 2
            let spawnRadius = rng.nextBetween(config.minSpawnRadius, config.maxSpawnRadius)
            let cos = cos(angle)
            let sin = sin(angle)
            let startPosition = CGPoint(
                x: center.x + cos * spawnRadius,
                y: center.y + sin * spawnRadius
            )
            let lifetime = rng.nextBetween(config.minLifetime, config.maxLifetime)
            let travelDistance = rng.nextBetween(
                avgDistance * config.distanceLimit * 0.5,
                avgDistance * config.distanceLimit
            )
            let speed = travelDistance / lifetime
            let sizeVariant = rng.next()
            let size: CGFloat
            if sizeVariant < 0.3 {
                size = config.baseSize * 0.67
            } else if sizeVariant < 0.7 {
                size = config.baseSize * 1.33
            } else {
                size = config.baseSize * 2.2
            }

            particles.append(
                SparkleParticle(
                    startPosition: startPosition,
                    velocity: CGPoint(x: cos * speed, y: sin * speed),
                    startTime: rng.next() * config.maxStartTimeDelay,
                    lifetime: lifetime,
                    size: size,
                    baseOpacity: rng.nextBetween(0.3, 0.8),
                    color: config.color.resolve(rng: &rng),
                    path: makeSparkleStarPath(size: size)
                )
            )
        }

        self.particles = particles
    }
}

public final class SparkleParticleBackgroundView: UIView {
    private var color: SparkleColorPair = defaultSparkleGradient {
        didSet {
            guard color != oldValue else {
                return
            }
            restartIdleSystem()
        }
    }

    public var centerShift: CGPoint = .zero {
        didSet {
            guard centerShift != oldValue else {
                return
            }
            restartIdleSystem()
        }
    }

    public var canvasSize: CGSize = CGSize(width: 350, height: 230) {
        didSet {
            guard canvasSize != oldValue else {
                return
            }
            restartIdleSystem()
        }
    }

    private var systems: [SparkleParticleSystem] = []
    private var displayLink: CADisplayLink?
    private let rotations = SparkleRotation.makeRotations()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else {
            ensureDisplayLink()
        }
    }

    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !systems.isEmpty else {
            return
        }

        let now = CACurrentMediaTime()
        context.saveGState()
        context.setBlendMode(.normal)
        context.translateBy(x: bounds.midX - canvasSize.width / 2, y: bounds.midY - canvasSize.height / 2)

        for system in systems {
            draw(system: system, at: CGFloat(now - system.startTime), in: context)
        }

        context.restoreGState()
    }

    public func burst() {
        let system = SparkleParticleSystem(config: .burst(color: color, centerShift: centerShift, canvasSize: canvasSize))
        systems.append(system)
        ensureDisplayLink()
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        restartIdleSystem()
    }

    private func restartIdleSystem() {
        systems = [SparkleParticleSystem(config: idleConfig())]
        setNeedsDisplay()
        if window != nil {
            ensureDisplayLink()
        }
    }

    private func idleConfig() -> SparkleParticleConfig {
        var config = SparkleParticleConfig()
        config.width = canvasSize.width
        config.height = canvasSize.height
        config.color = color
        config.centerShift = centerShift
        return config
    }

    private func ensureDisplayLink() {
        guard displayLink == nil else {
            return
        }
        let displayLink = CADisplayLink(target: self, selector: #selector(tick))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        } else {
            displayLink.preferredFramesPerSecond = 60
        }
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        systems.removeAll { system in
            system.config.selfDestroyTime > 0 && now - system.startTime >= system.config.selfDestroyTime
        }
        setNeedsDisplay()
    }

    private func draw(system: SparkleParticleSystem, at time: CGFloat, in context: CGContext) {
        let config = system.config
        let globalFadeIn = min(time / config.fadeInTime, 1)

        for particle in system.particles {
            let totalAge = time - particle.startTime
            let age = positiveModulo(totalAge, particle.lifetime)
            let lifeRatio = age / particle.lifetime
            let rotationIndex = positiveModulo(Int(floor(totalAge / particle.lifetime)), rotations.count)
            let rotation = rotations[rotationIndex]
            let startOffset = CGPoint(
                x: particle.startPosition.x - system.center.x,
                y: particle.startPosition.y - system.center.y
            )
            let rotatedStartOffset = rotation.apply(to: startOffset)
            let rotatedVelocity = rotation.apply(to: particle.velocity)
            let speedMultiplier = 1 + config.accelerationFactor * exp(-3 * lifeRatio)
            let position = CGPoint(
                x: system.center.x + rotatedStartOffset.x + rotatedVelocity.x * age * speedMultiplier,
                y: system.center.y + rotatedStartOffset.y + rotatedVelocity.y * age * speedMultiplier
            )

            let opacity = particleOpacity(
                particle: particle,
                position: position,
                lifeRatio: lifeRatio,
                globalFadeIn: globalFadeIn,
                config: config
            )
            guard opacity > 0 else {
                continue
            }

            context.saveGState()
            context.translateBy(x: position.x, y: position.y)
            context.setAlpha(opacity)
            particle.color.setFill()
            context.addPath(particle.path)
            context.fillPath()
            context.restoreGState()
        }
    }

    private func particleOpacity(
        particle: SparkleParticle,
        position: CGPoint,
        lifeRatio: CGFloat,
        globalFadeIn: CGFloat,
        config: SparkleParticleConfig
    ) -> CGFloat {
        var opacity: CGFloat = 1
        if lifeRatio < config.fadeInTime / particle.lifetime {
            opacity = (lifeRatio * particle.lifetime) / config.fadeInTime
        } else if lifeRatio > 1 - config.fadeOutTime / particle.lifetime {
            opacity = (1 - lifeRatio) * particle.lifetime / config.fadeOutTime
        }
        opacity *= particle.baseOpacity * globalFadeIn

        let distanceToEdge = min(
            min(position.x, config.width - position.x),
            min(position.y, config.height - position.y)
        )
        if distanceToEdge < config.edgeFadeZone {
            opacity *= max(0, distanceToEdge / config.edgeFadeZone)
        }

        return max(0, min(opacity, 1))
    }
}

public struct SparkleParticleBackground: UIViewRepresentable {
    public var centerShift: CGPoint
    public var canvasSize: CGSize
    @Binding public var burstTrigger: Int

    public init(
        centerShift: CGPoint = .zero,
        canvasSize: CGSize = CGSize(width: 350, height: 230),
        burstTrigger: Binding<Int> = .constant(0)
    ) {
        self.centerShift = centerShift
        self.canvasSize = canvasSize
        self._burstTrigger = burstTrigger
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(burstTrigger: burstTrigger)
    }

    public func makeUIView(context: Context) -> SparkleParticleBackgroundView {
        let view = SparkleParticleBackgroundView()
        view.centerShift = centerShift
        view.canvasSize = canvasSize
        return view
    }

    public func updateUIView(_ uiView: SparkleParticleBackgroundView, context: Context) {
        uiView.centerShift = centerShift
        uiView.canvasSize = canvasSize
        if burstTrigger != context.coordinator.burstTrigger {
            context.coordinator.burstTrigger = burstTrigger
            uiView.burst()
        }
    }

    public final class Coordinator {
        var burstTrigger: Int

        init(burstTrigger: Int) {
            self.burstTrigger = burstTrigger
        }
    }
}

private struct SeededRandom {
    private var seed: CGFloat

    init(seed: Int) {
        self.seed = CGFloat(seed)
    }

    mutating func next() -> CGFloat {
        seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
        return seed / 233280
    }

    mutating func nextBetween(_ min: CGFloat, _ max: CGFloat) -> CGFloat {
        min + (max - min) * next()
    }
}

private struct SparkleRotation {
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let d: CGFloat

    func apply(to point: CGPoint) -> CGPoint {
        CGPoint(
            x: a * point.x + c * point.y,
            y: b * point.x + d * point.y
        )
    }

    static func makeRotations() -> [SparkleRotation] {
        (0..<18).map { index in
            let angle = 220 * CGFloat.pi / 180 * CGFloat(index)
            return SparkleRotation(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle))
        }
    }
}

private func positiveModulo(_ value: CGFloat, _ divisor: CGFloat) -> CGFloat {
    value - divisor * floor(value / divisor)
}

private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
    let remainder = value % divisor
    return remainder >= 0 ? remainder : remainder + divisor
}

private func makeSparkleStarPath(size: CGFloat) -> CGPath {
    let scale = size
    let innerSize = 0.12 * scale
    let armLength = 0.45 * scale
    let armWidth = 0.08 * scale
    let tipWidth = armWidth * 0.2

    let path = CGMutablePath()
    path.move(to: CGPoint(x: -armWidth, y: -innerSize))
    path.addLine(to: CGPoint(x: -tipWidth, y: -armLength))
    path.addLine(to: CGPoint(x: tipWidth, y: -armLength))
    path.addLine(to: CGPoint(x: armWidth, y: -innerSize))
    path.addLine(to: CGPoint(x: innerSize, y: -innerSize))
    path.addLine(to: CGPoint(x: innerSize, y: -armWidth))
    path.addLine(to: CGPoint(x: armLength, y: -tipWidth))
    path.addLine(to: CGPoint(x: armLength, y: tipWidth))
    path.addLine(to: CGPoint(x: innerSize, y: armWidth))
    path.addLine(to: CGPoint(x: innerSize, y: innerSize))
    path.addLine(to: CGPoint(x: armWidth, y: innerSize))
    path.addLine(to: CGPoint(x: tipWidth, y: armLength))
    path.addLine(to: CGPoint(x: -tipWidth, y: armLength))
    path.addLine(to: CGPoint(x: -armWidth, y: innerSize))
    path.addLine(to: CGPoint(x: -innerSize, y: innerSize))
    path.addLine(to: CGPoint(x: -innerSize, y: armWidth))
    path.addLine(to: CGPoint(x: -armLength, y: tipWidth))
    path.addLine(to: CGPoint(x: -armLength, y: -tipWidth))
    path.addLine(to: CGPoint(x: -innerSize, y: -armWidth))
    path.addLine(to: CGPoint(x: -innerSize, y: -innerSize))
    path.addLine(to: CGPoint(x: -armWidth, y: -innerSize))
    path.closeSubpath()
    return path
}
