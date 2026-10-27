import UIKit
import Combine

public enum CardBalanceConcealment: Int, CaseIterable {
    case mask, particles
    var title: String { self == .particles ? "Частицы" : "Маска" }
}

public enum CardParticleEffect: Int, Codable, CaseIterable {
    case wave, disintegrate
}

/// Distances are points; angles are degrees; timing fractions are 0...1.
/// A single list drives controls, persistence and Swift export to keep them in sync.
public struct CardDisintegrationSettings: Codable, Equatable {
    var hideDuration: CGFloat = 0.7
    var revealDuration: CGFloat = 0.6
    var travel: CGFloat = 4
    var lift: CGFloat = 0
    var originInfluence: CGFloat = 0.15
    var destinationMix: CGFloat = 0.08
    var turbulence: CGFloat = 0.15
    var stagger: CGFloat = 0.12
    var timingRandomness: CGFloat = 0.04
    var rotation: CGFloat = 10
    var fragmentSize: CGFloat = 2.4
    var finalSize: CGFloat = 1
    var easing: CGFloat = 1
    var blendStart: CGFloat = 0.42
    var blendDuration: CGFloat = 0.35
    static let calm = Self()
    static var expressive: Self {
        var s = Self()
        s.hideDuration = 1.05; s.revealDuration = 1.05
        s.travel = 24; s.lift = 21; s.originInfluence = 1; s.destinationMix = 1
        s.turbulence = 0.5; s.stagger = 0.22; s.timingRandomness = 0.08
        s.rotation = 86; s.finalSize = 1.3; s.easing = 0.5
        s.blendStart = 0.60; s.blendDuration = 0.30
        return s
    }
    struct Control {
        let key: String
        let title: String
        let path: WritableKeyPath<CardDisintegrationSettings, CGFloat>
        let range: ClosedRange<CGFloat>
        let unit: String
        let group: String
    }
    static let controls: [Control] = [
        .init(key: "hideDuration", title: "Длительность скрытия", path: \.hideDuration, range: 0.2...3, unit: "s", group: "Время"),
        .init(key: "revealDuration", title: "Длительность раскрытия", path: \.revealDuration, range: 0.2...3, unit: "s", group: "Время"),
        .init(key: "stagger", title: "Волна от места нажатия", path: \.stagger, range: 0...0.6, unit: "%", group: "Время"),
        .init(key: "timingRandomness", title: "Случайная задержка", path: \.timingRandomness, range: 0...0.3, unit: "%", group: "Время"),
        .init(key: "easing", title: "Плавность разгона и остановки", path: \.easing, range: 0...1, unit: "%", group: "Время"),
        .init(key: "travel", title: "Дальность разлёта", path: \.travel, range: 0...100, unit: "pt", group: "Траектория"),
        .init(key: "lift", title: "Подъём вверх / вниз", path: \.lift, range: -80...80, unit: "pt", group: "Траектория"),
        .init(key: "originInfluence", title: "Влияние места нажатия", path: \.originInfluence, range: 0...1, unit: "%", group: "Траектория"),
        .init(key: "destinationMix", title: "Перемешивание по всей сумме", path: \.destinationMix, range: 0...1, unit: "%", group: "Траектория"),
        .init(key: "turbulence", title: "Случайность траекторий", path: \.turbulence, range: 0...1, unit: "%", group: "Траектория"),
        .init(key: "rotation", title: "Вращение фрагментов", path: \.rotation, range: 0...360, unit: "°", group: "Фрагменты"),
        .init(key: "fragmentSize", title: "Размер фрагментов", path: \.fragmentSize, range: 0.8...8, unit: "pt", group: "Фрагменты"),
        .init(key: "finalSize", title: "Размер перед растворением", path: \.finalSize, range: 0.2...4, unit: "×", group: "Фрагменты"),
        .init(key: "blendStart", title: "Начало перехода в облако", path: \.blendStart, range: 0.1...0.75, unit: "%", group: "Переход в облако"),
        .init(key: "blendDuration", title: "Длительность перехода", path: \.blendDuration, range: 0.1...0.65, unit: "%", group: "Переход в облако")
    ]
    var clamped: Self {
        var result = self
        for c in Self.controls {
            let value = result[keyPath: c.path]
            result[keyPath: c.path] = value.isFinite ? min(c.range.upperBound, max(c.range.lowerBound, value)) : Self.calm[keyPath: c.path]
        }
        return result
    }
    // Leave a settling tail in which only the live cloud is visible. Removing the
    // snapshot cannot change a pixel or restart the cloud's phase on the last frame.
    var blendEnd: CGFloat { min(0.95, blendStart + blendDuration) }
    func cloudOpacity(at progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, (progress - blendStart) / (blendEnd - blendStart)))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}

public struct CardParticleSettings: Codable, Equatable {
    var size: CGFloat = 1
    var frequency: CGFloat = 1
    var spread: CGFloat = 4
    var effect: CardParticleEffect = .wave
    var disintegration: CardDisintegrationSettings = .calm
    static let original = Self()

    init(size: CGFloat = 1, frequency: CGFloat = 1, spread: CGFloat = 4, effect: CardParticleEffect = .wave, disintegration: CardDisintegrationSettings = .calm) {
        self.size = size; self.frequency = frequency; self.spread = spread; self.effect = effect; self.disintegration = disintegration
    }
    private enum CodingKeys: String, CodingKey { case size, frequency, spread, effect, disintegration }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        size = try values.decodeIfPresent(CGFloat.self, forKey: .size) ?? 1
        frequency = try values.decodeIfPresent(CGFloat.self, forKey: .frequency) ?? 1
        spread = try values.decodeIfPresent(CGFloat.self, forKey: .spread) ?? 4
        effect = CardParticleEffect(rawValue: try values.decodeIfPresent(Int.self, forKey: .effect) ?? 0) ?? .wave
        disintegration = try values.decodeIfPresent(CardDisintegrationSettings.self, forKey: .disintegration) ?? .calm
    }

    var clamped: Self {
        Self(size: min(3, max(0.4, size)), frequency: min(3, max(0.25, frequency)), spread: min(24, max(0, spread)), effect: effect, disintegration: disintegration.clamped)
    }

}

/// A bounded local force, with a critically damped return to the live dust field.
/// It changes neither the particle's anchor nor its lifetime/opacity.
struct CardParticleRepulsion {
    private(set) var offset = CGPoint.zero
    private var velocity = CGPoint.zero
    static let radius: CGFloat = 64
    static let travel: CGFloat = 40
    private let reach: CGFloat
    private let strength: CGFloat
    private let deflection: CGFloat
    private let response: CGFloat

    init(variation: Double? = nil) {
        if let variation {
            func sample(_ salt: Double) -> CGFloat {
                let value = sin(variation * 127.1 + salt) * 43758.5453
                return CGFloat(value - floor(value))
            }
            reach = 0.82 + sample(1.7) * 0.36
            strength = 0.4 + sample(8.3) * 0.6
            deflection = (sample(24.9) - 0.5) * 0.65
            response = 0.8 + sample(63.1) * 0.4
        } else { reach = 1; strength = 1; deflection = 0; response = 1 }
    }
    var isDisplaced: Bool { offset != .zero || velocity != .zero }
    mutating func reset() { offset = .zero; velocity = .zero }

    mutating func advance(at point: CGPoint, finger: CGPoint?, fallbackDirection: CGPoint, by interval: TimeInterval) {
        guard interval.isFinite, interval > 0 else { return }
        var target = CGPoint.zero
        if let finger {
            let delta = CGPoint(x: point.x - finger.x, y: point.y - finger.y)
            let distance = hypot(delta.x, delta.y)
            if distance < Self.radius * reach {
                let direction = distance > 0.001 ? delta : fallbackDirection
                let length = max(0.001, hypot(direction.x, direction.y))
                let fraction = distance / (Self.radius * reach)
                let falloff = 1 - fraction * fraction * (3 - 2 * fraction)
                // Stable variation per particle avoids a hard circular rim.
                // Nothing is re-randomized each frame, so the return stays smooth.
                let travel = Self.travel * strength * falloff
                target = CGPoint(x: (direction.x - direction.y * deflection) / length * travel,
                                 y: (direction.y + direction.x * deflection) / length * travel)
            }
        }
        guard target != .zero || offset != .zero || velocity != .zero else { return }
        let rate: CGFloat = (target == .zero ? 14 : 24) * response
        let dt = CGFloat(interval)
        let decay = exp(-rate * dt)
        func step(_ position: CGFloat, _ speed: CGFloat, _ destination: CGFloat) -> (CGFloat, CGFloat) {
            let delta = position - destination
            let impulse = speed + rate * delta
            return (destination + (delta + impulse * dt) * decay,
                    (speed - rate * impulse * dt) * decay)
        }
        (offset.x, velocity.x) = step(offset.x, velocity.x, target.x)
        (offset.y, velocity.y) = step(offset.y, velocity.y, target.y)
        if target == .zero, hypot(offset.x, offset.y) < 0.001, hypot(velocity.x, velocity.y) < 0.005 {
            offset = .zero; velocity = .zero
        }
    }
}

/// Native spoiler dust inspired by Telegram iOS InvisibleInkDustNode.
/// Shares particle state between Metal drawing, the fallback and disintegration.
@MainActor
final class CardSpoilerDustView: UIView {
    private struct Particle {
        var anchor: CGPoint
        var drift: CGPoint
        var phase: Double
        var opacity: CGFloat
        var radius: CGFloat
        var repulsion = CardParticleRepulsion()
        var layoutOffset = CGPoint.zero
        var densityOpacity: CGFloat = 1
    }
    private var particles: [Particle] = []
    private var tuning = CardParticleSettings.original.clamped
    private var samplesDirty = true
    private var dynamicsPending = false
    private(set) var dynamicsStepCount = 0
    private var cachedSamples: [TransitionSample] = []
    private(set) var transitionHorizontalBounds: CGRect?
    private var metal: CardDustMetalView?
    private var metalUnavailable = false
    #if DEBUG
    private(set) var rasterDrawCount = 0
    #endif
    private var particleSeed: UInt64 = 0xCA4D51DE
    private var link: CADisplayLink?
    private var previousTime: CFTimeInterval = 0
    private var time: CFTimeInterval = 0
    var nextOrigin: CGPoint?
    private(set) var transitionOrigin = CGPoint.zero
    private var transition: (elapsed: TimeInterval, concealing: Bool)?
    private var observers: [NSObjectProtocol] = []
    private var policyObservation: AnyCancellable?
    private(set) var isConcealed = false
    private(set) var particleColor: UIColor = .white
    private(set) var particleGradient: [UIColor]?
    private(set) var interactionPoint: CGPoint?
    var gradientFrame = CGRect.zero {
        didSet { if oldValue != gradientFrame, particleGradient != nil { updateMetalPalette(); requestDisplay() } }
    }
    var isAnimating: Bool { link != nil }
    var particleCount: Int { particles.count }
    var maximumInteractionOffset: CGFloat {
        particles.reduce(0) { max($0, hypot($1.repulsion.offset.x, $1.repulsion.offset.y)) }
    }
    struct TransitionSample {
        var position: CGPoint
        var diameter: CGFloat
        var opacity: CGFloat
        var rawOpacity: CGFloat = 0
    }
    private func prepareSamples() {
        guard samplesDirty else { return }
        samplesDirty = false
        cachedSamples.removeAll(keepingCapacity: true)
        cachedSamples.reserveCapacity(particles.count)
        for particle in particles {
            let age = (time + particle.phase).truncatingRemainder(dividingBy: 1)
            let drift = (age - 0.5) * 2 * tuning.spread
            let point = CGPoint(x: particle.anchor.x + particle.layoutOffset.x + particle.drift.x * drift,
                                y: particle.anchor.y + particle.layoutOffset.y + particle.drift.y * drift)
            let envelope = CGFloat(sin(.pi * age))
            let opacity = particle.opacity * envelope * envelope * particle.densityOpacity
            var position = CGPoint(x: point.x + particle.repulsion.offset.x, y: point.y + particle.repulsion.offset.y)
            if let extent = transitionHorizontalBounds, fieldRect.width > 0 {
                position.x = extent.minX + (position.x - fieldRect.minX) / fieldRect.width * extent.width
            }
            cachedSamples.append(TransitionSample(position: position,
                diameter: particle.radius * tuning.size * 2, opacity: quantizedOpacity(opacity), rawOpacity: opacity))
        }
    }
    private func quantizedOpacity(_ opacity: CGFloat) -> CGFloat {
        opacity > 0.005 ? CGFloat(min(63, max(0, Int(opacity * 64))) + 1) / 64 : 0
    }
    // Expand the live cloud itself, keeping circular dots, particle identities and
    // their phases. The hidden field always finishes at its fixed privacy width.
    func setTransitionFootprint(_ source: CGRect?, progress: CGFloat = 1) {
        let t = min(1, max(0, progress))
        let eased = t * t * t * (t * (t * 6 - 15) + 10)
        let extent: CGRect?
        if let source, !source.isEmpty, t < 1 {
            extent = CGRect(x: source.minX + (fieldRect.minX - source.minX) * eased,
                            y: fieldRect.minY,
                            width: source.width + (fieldRect.width - source.width) * eased,
                            height: fieldRect.height)
        } else { extent = nil }
        guard extent != transitionHorizontalBounds else { return }
        transitionHorizontalBounds = extent
        requestDisplay()
    }

    func transitionSamples(offset: CGPoint = .zero) -> [TransitionSample] {
        prepareSamples()
        guard offset != .zero else { return cachedSamples }
        return cachedSamples.map {
            var sample = $0
            sample.position.x += offset.x; sample.position.y += offset.y
            return sample
        }
    }
    private func drawingSamples() -> [TransitionSample] {
        prepareSamples()
        guard let transition else { return cachedSamples }
        let progress = min(1, transition.elapsed / 0.7)
        let reach = max(1, hypot(fieldRect.width, fieldRect.height))
        return zip(particles, cachedSamples).map { particle, value in
            var sample = value
            let dx = particle.anchor.x - transitionOrigin.x, dy = particle.anchor.y - transitionOrigin.y
            let distance = max(1, hypot(dx, dy))
            let local = min(1, max(0, (progress - min(1, distance / reach) * 0.32) / 0.68))
            let eased = 1 - pow(1 - local, 3)
            let travel = 12 + tuning.spread * 3
            let scatter = transition.concealing ? sin(.pi * local) * travel * 0.45 : eased * travel
            sample.position.x += dx / distance * scatter
            sample.position.y += dy / distance * scatter
            sample.opacity = quantizedOpacity(sample.rawOpacity * (transition.concealing ? CGFloat(min(1, local * 4)) : CGFloat(1 - eased)))
            return sample
        }
    }
    var settings = CardParticleSettings.original {
        didSet {
            guard settings != oldValue else { return }
            tuning = settings.clamped
            if settings.frequency != oldValue.frequency { rebuildParticles() }
            requestDisplay()
        }
    }
    var fieldCornerRadius: CGFloat { fieldRect.height / 2 }
    var animationActive = false { didSet { if animationActive != oldValue { updateActivity() } } }
    var fieldRect = CGRect.zero {
        didSet {
            guard oldValue != fieldRect else { return }
            resizeParticles(from: oldValue)
            requestDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isHidden = true
        contentMode = .redraw
        policyObservation = HeroParticleAnimationPolicy.observe { [weak self] in self?.updateActivity() }
        for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification,
                     UIAccessibility.reduceMotionStatusDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    self?.updateActivity(forceInactive: note.name == UIApplication.willResignActiveNotification)
                }
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    // Older iOS concurrency runtimes can crash in isolated deinit (Swift #85663).
    // Cleanup only invalidates resources; it does not touch actor-isolated UI.
    deinit {
        link?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func setColor(_ color: UIColor) {
        guard particleGradient != nil || !particleColor.isEqual(color) else { return }
        particleGradient = nil
        particleColor = color
        updateMetalPalette()
        requestDisplay()
    }
    func setGradient(_ colors: [UIColor]) {
        guard particleGradient != colors else { return }
        particleGradient = colors
        particleColor = colors.first ?? .white
        updateMetalPalette()
        requestDisplay()
    }
    func setConcealed(_ concealed: Bool, animated: Bool) {
        guard concealed != isConcealed else { return }
        isConcealed = concealed
        if !concealed { interactionPoint = nil }
        transitionOrigin = nextOrigin ?? CGPoint(x: fieldRect.midX, y: fieldRect.midY)
        nextOrigin = nil
        if animated, animationActive, window != nil, !UIAccessibility.isReduceMotionEnabled {
            // Use the same origin as the live text wipe.
            transition = (0, concealed)
            isHidden = false
        } else {
            transition = nil
            isHidden = !concealed
        }
        requestDisplay()
        updateActivity()
    }
    func setInteractionPoint(_ point: CGPoint?) {
        guard animationActive, isAnimating, isConcealed, window != nil,
              UIApplication.shared.applicationState == .active, !UIAccessibility.isReduceMotionEnabled,
              let point, point.x.isFinite, point.y.isFinite else {
            interactionPoint = nil
            return
        }
        interactionPoint = point
        dynamicsPending = true
    }
    func reset() {
        setTransitionFootprint(nil)
        setColor(.white)
        transition = nil
        isConcealed = false
        isHidden = true
        animationActive = false
        fieldRect = .zero
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { metal?.removeFromSuperview(); metal = nil }
        updateActivity()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        contentScaleFactor = max(1, window?.screen.scale ?? traitCollection.displayScale)
        updateMetalPalette()
        requestDisplay()
    }
    private func updateActivity(forceInactive: Bool = false) {
        updateMetalRenderer()
        let shouldRun = animationActive && HeroParticleAnimationPolicy.allowsAnimation && !forceInactive && window != nil
            && UIApplication.shared.applicationState == .active
            && !UIAccessibility.isReduceMotionEnabled && (isConcealed || transition != nil)
        if shouldRun {
            guard link == nil else { return }
            previousTime = 0
            let proxy = DustDisplayLinkTarget(view: self)
            let link = CADisplayLink(target: proxy, selector: #selector(DustDisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            link?.invalidate(); link = nil
            interactionPoint = nil
            for index in particles.indices {
                particles[index].repulsion.reset()
                particles[index].layoutOffset = .zero
            }
            transition = nil
            isHidden = !isConcealed
            requestDisplay()
        }
    }
    fileprivate func tick(_ link: CADisplayLink) {
        let dt = previousTime == 0 ? 1.0 / 60 : min(1.0 / 15, max(0, link.timestamp - previousTime))
        previousTime = link.timestamp
        advance(by: dt)
    }
    func advance(by interval: TimeInterval) {
        guard interval.isFinite, interval > 0 else { return }
        let dt = min(1.0 / 15, interval)
        time += dt
        let spread = tuning.spread
        let layoutDecay = exp(-12 * dt)
        let densityBlend = 1 - exp(-10 * dt)
        let desiredCount = desiredParticleCount
        if dynamicsPending || interactionPoint != nil {
            dynamicsStepCount += 1
            dynamicsPending = false
            for index in particles.indices {
                let targetOpacity: CGFloat = index < desiredCount ? 1 : 0
                particles[index].densityOpacity += (targetOpacity - particles[index].densityOpacity) * densityBlend
                particles[index].layoutOffset.x *= layoutDecay
                particles[index].layoutOffset.y *= layoutDecay
                if abs(targetOpacity - particles[index].densityOpacity) < 0.000001 { particles[index].densityOpacity = targetOpacity }
                if abs(particles[index].layoutOffset.x) + abs(particles[index].layoutOffset.y) < 0.000001 { particles[index].layoutOffset = .zero }
                if interactionPoint != nil || particles[index].repulsion.isDisplaced {
                    let particle = particles[index]
                    let point = restingPosition(of: particle, spread: spread)
                    particles[index].repulsion.advance(at: point, finger: interactionPoint,
                        fallbackDirection: particle.drift, by: dt)
                }
            }
            // Settled clouds only need their procedural samples, not thousands of
            // per-frame array mutations. Interaction and resizing wake this path.
            for particle in particles where particle.repulsion.isDisplaced || particle.layoutOffset != .zero
                || (particle.densityOpacity != 0 && particle.densityOpacity != 1) { dynamicsPending = true; break }
        }
        while particles.count > desiredCount, let last = particles.last, last.densityOpacity < 0.001 {
            particles.removeLast()
        }
        if var value = transition {
            value.elapsed += dt
            if value.elapsed >= 0.7 {
                transition = nil
                isHidden = !isConcealed
                updateActivity()
            } else { transition = value }
        }
        requestDisplay()
    }
    private func restingPosition(of particle: Particle, spread: CGFloat) -> CGPoint {
        let age = (time + particle.phase).truncatingRemainder(dividingBy: 1)
        return CGPoint(x: particle.anchor.x + particle.layoutOffset.x + particle.drift.x * (age - 0.5) * 2 * spread,
                       y: particle.anchor.y + particle.layoutOffset.y + particle.drift.y * (age - 0.5) * 2 * spread)
    }
    private func resizeParticles(from oldRect: CGRect) {
        guard isAnimating, isConcealed, !particles.isEmpty, oldRect.width > 0, oldRect.height > 0,
              fieldRect.width > 0, fieldRect.height > 0 else {
            rebuildParticles()
            return
        }
        dynamicsPending = true
        // Balance refreshes change glyph/pill widths. Keep each particle and its
        // phase instead of reseeding the whole cloud on every layout change.
        // Its current position remains exact, then eases into the new capsule.
        let radius = min(fieldRect.width, fieldRect.height) / 2
        for index in particles.indices {
            let old = particles[index].anchor
            let y = fieldRect.minY + (old.y - oldRect.minY) / oldRect.height * fieldRect.height
            let edgeY = max(0, abs(y - fieldRect.midY) - (fieldRect.height / 2 - radius))
            let inset = radius - sqrt(max(0, radius * radius - edgeY * edgeY))
            let x = fieldRect.minX + (old.x - oldRect.minX) / oldRect.width * fieldRect.width
            let next = CGPoint(x: min(fieldRect.maxX - inset, max(fieldRect.minX + inset, x)), y: y)
            particles[index].layoutOffset.x += old.x - next.x
            particles[index].layoutOffset.y += old.y - next.y
            particles[index].anchor = next
        }
        // Add/remove density gradually too, including the initial layout from
        // a tiny placeholder into a full amount. Existing particles keep moving.
        appendParticles(until: desiredParticleCount, opacity: 0)
    }
    private var desiredParticleCount: Int {
        guard fieldRect.width > 0, fieldRect.height > 0 else { return 0 }
        return min(6000, max(24, Int(fieldRect.width * fieldRect.height * 0.28 * tuning.frequency)))
    }
    private func rebuildParticles() {
        dynamicsPending = false
        particles.removeAll(keepingCapacity: true)
        particleSeed = 0xCA4D51DE
        appendParticles(until: desiredParticleCount, opacity: 1)
    }
    private func appendParticles(until count: Int, opacity: CGFloat) {
        guard count > particles.count else { return }
        // Telegram's dust density is proportional to text area (0.35 / pt²),
        // with ~1 s lifetimes and up to 20 pt/s drift. Cap the larger balance.
        func random() -> CGFloat {
            particleSeed = particleSeed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(particleSeed >> 32) / CGFloat(UInt32.max)
        }
        let shape = UIBezierPath(roundedRect: fieldRect, cornerRadius: fieldCornerRadius)
        for _ in particles.count..<count {
            var point: CGPoint
            repeat {
                point = CGPoint(x: fieldRect.minX + random() * fieldRect.width,
                                y: fieldRect.minY + random() * fieldRect.height)
            } while !shape.contains(point)
            let angle = random() * .pi * 2, speed = 0.25 + random() * 0.75
            let phase = Double(random())
            particles.append(Particle(anchor: point, drift: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed),
                                      phase: phase, opacity: 0.35 + random() * 0.65,
                                      radius: 0.35 + random() * 0.35, repulsion: CardParticleRepulsion(variation: phase), densityOpacity: opacity))
        }
    }
    private func updateMetalPalette() {
        metal?.setPalette(color: particleColor, gradient: particleGradient, frame: gradientFrame, traits: traitCollection)
    }
    private func updateMetalRenderer() {
        guard window != nil, !bounds.isEmpty, isConcealed || transition != nil else {
            metal?.removeFromSuperview(); metal = nil
            return
        }
        guard metal == nil, !metalUnavailable else { return }
        guard let renderer = CardDustMetalView(particleCapacity: 6000) else { metalUnavailable = true; return }
        metal = renderer
        renderer.frame = bounds
        renderer.samples = { [weak self] in self?.drawingSamples() ?? [] }
        renderer.onFirstFrame = { [weak self, weak renderer] in
            guard let self, self.metal === renderer else { return }
            self.layer.contents = nil
        }
        updateMetalPalette()
        addSubview(renderer)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        updateMetalRenderer()
        metal?.frame = bounds
        requestDisplay()
    }
    private func requestDisplay() {
        samplesDirty = true
        if let metal { metal.setNeedsDisplay() }
        else { setNeedsDisplay() }
    }
    #if DEBUG
    func metalSnapshotForValidation(scale: CGFloat = 3) -> UIImage? {
        let renderer = CardDustMetalView(particleCapacity: 6000)
        renderer?.setPalette(color: particleColor, gradient: particleGradient, frame: gradientFrame, traits: traitCollection)
        return renderer?.snapshotForValidation(samples: drawingSamples(), size: bounds.size, scale: scale)
    }
    #endif
    override func draw(_ rect: CGRect) {
        // Layout/theme invalidation can request a raster draw after Metal starts.
        // Keep that backing layer empty instead of compositing the dust twice.
        guard metal?.alpha != 1 else { return }
        #if DEBUG
        rasterDrawCount += 1
        #endif
        guard let context = UIGraphicsGetCurrentContext(), !particles.isEmpty else { return }
        let paths = (0..<64).map { _ in CGMutablePath() }
        for sample in drawingSamples() where sample.opacity > 0 {
            let bucket = min(63, max(0, Int((sample.opacity * 64).rounded()) - 1))
            let radius = sample.diameter / 2
            paths[bucket].addEllipse(in: CGRect(x: sample.position.x - radius, y: sample.position.y - radius,
                                               width: sample.diameter, height: sample.diameter))
        }
        // Draw the existing dust alpha once, then color it with exactly the
        // amount's palette and radial geometry. Keep the field independent of
        // glyphs, including while particles scatter beyond the hidden amount.
        let usesGradient = particleGradient != nil && gradientFrame.width > 0
        if usesGradient { context.saveGState(); context.beginTransparencyLayer(auxiliaryInfo: nil) }
        let color = (usesGradient ? UIColor.white : particleColor).resolvedColor(with: traitCollection)
        for (index, path) in paths.enumerated() {
            context.setFillColor(color.withAlphaComponent(CGFloat(index + 1) / 64).cgColor)
            context.addPath(path); context.fillPath()
        }
        if usesGradient {
            if let colors = particleGradient,
               let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: colors.map { $0.resolvedColor(with: traitCollection).cgColor } as CFArray, locations: nil) {
                let geometry = MtwCardForegroundView.radialGeometry(in: gradientFrame, style: .balance)
                context.setBlendMode(.sourceIn)
                context.drawRadialGradient(gradient, startCenter: geometry.center, startRadius: 0,
                    endCenter: geometry.center, endRadius: geometry.radius,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            context.endTransparencyLayer(); context.restoreGState()
        }
    }
}

@MainActor
private final class DustDisplayLinkTarget: NSObject {
    weak var view: CardSpoilerDustView?
    init(view: CardSpoilerDustView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { view?.tick(link) }
}
