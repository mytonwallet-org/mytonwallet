import UIKit

private struct WelcomeParticle {
    var angle = CGFloat.random(in: 0..<(2 * .pi))
    var radius = CGFloat.random(in: 55...70)
    var travel = CGFloat.random(in: 0.225...0.45)
    var baseOpacity = CGFloat.random(in: 0.1...0.7)
    var duration = CGFloat.random(in: 3...5)
    var isBurst = false
    var progress: CGFloat
    var opacity: CGFloat
    var fadeInAge: CGFloat
    var fadeOutAge: CGFloat?
    var fadeOutOpacity: CGFloat = 1
    var fadeOutStart: CGFloat = 0.65
    var fadeOutSlope: CGFloat = 1
    var isWaiting = false

    init(phase: CGFloat) {
        progress = phase
        opacity = phase > 0.65 ? 1 - welcomeEase((phase - 0.65) / 0.35) : welcomeEase(phase * 4 / 0.25)
        fadeInAge = min(phase * 4, 0.25)
        fadeOutAge = phase > 0.65 ? (phase - 0.65) / 0.35 : nil
    }

    mutating func advance(elapsed: CGFloat, speed: CGFloat) {
        guard !isWaiting else { return }
        if let age = fadeOutAge {
            let nextAge = age + elapsed
            fadeOutAge = nextAge
            let time = min(1, nextAge)
            let travel = time + (fadeOutSlope - 1) * time * pow(1 - time, 2)
            progress = fadeOutStart + (1 - fadeOutStart) * travel
            opacity = fadeOutOpacity * (1 - welcomeEase(time))
            if time == 1 {
                progress = 0
                fadeInAge = 0
                fadeOutAge = nil
                isWaiting = true
            }
        } else {
            progress = min(1, progress + elapsed * speed / duration)
            fadeInAge += elapsed
            opacity = welcomeEase(fadeInAge / (isBurst ? 0.05 : 0.25))
            if progress >= 0.65 {
                fadeOutAge = 0
                fadeOutOpacity = opacity
                fadeOutStart = progress
                fadeOutSlope = min(3, speed / (duration * (1 - progress)))
            }
        }
    }
}

private func welcomeEase(_ progress: CGFloat) -> CGFloat {
    (1 - cos(.pi * min(1, progress))) / 2
}

final class WelcomeParticleStream {
    private static let placements: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (27, 65, 10, 0.3), (51, 165, 10, 0.2), (288, 64, 10, 0.3), (227, 34, 10, 0.1),
        (303, 131, 6, 0.2), (308, 29, 6, 0.3), (54, 0, 6, 0.4), (316, 151, 6, 0.1),
        (310, 198, 6, 0.4), (21, 149, 6, 0.4), (65, 119, 6, 0.2), (0, 107, 6, 0.1),
        (67, 41, 15, 0.4), (135, 10, 15, 0.15), (10, 11, 15, 0.1), (246, 89, 15, 0.3),
        (262, 137, 15, 0.2), (189, 20, 10, 0.3),
    ]

    private var particles = WelcomeParticleStream.placements.indices.map {
        WelcomeParticle(phase: CGFloat($0) / CGFloat(WelcomeParticleStream.placements.count))
    }
    private var timeUntilNext: CGFloat = 0
    private var nextIndex = 0
    private var speed: CGFloat = 1
    private var density: CGFloat = 1
    private var wasPressed = false
    private let path = makeWelcomeParticlePath()

    func resetInteraction() {
        speed = 1
        density = 1
        wasPressed = false
    }

    func advance(elapsed: CGFloat, isHovered: Bool, isPressed: Bool) {
        if isPressed && !wasPressed { emitBurst() }
        wasPressed = isPressed
        let target: CGFloat = isPressed ? 6 : isHovered ? 3 : 1
        let smoothing: CGFloat = target > speed ? 0.18 : 0.55
        speed += (target - speed) * (1 - exp(-elapsed / smoothing))
        if abs(target - speed) < 0.005 { speed = target }
        let targetDensity: CGFloat = isPressed ? 3 : isHovered ? 2 : 1
        density += (targetDensity - density) * (1 - exp(-elapsed / smoothing))
        let targetCount = Int((CGFloat(Self.placements.count) * min(3, max(1, density))).rounded())
        while particles.count < targetCount {
            var particle = WelcomeParticle(phase: 0)
            particle.isWaiting = true
            particles.append(particle)
        }
        for index in particles.indices {
            particles[index].advance(elapsed: elapsed, speed: speed)
        }
        timeUntilNext -= elapsed
        guard timeUntilNext <= 0 else { return }
        guard particles.filter({ !$0.isWaiting }).count < targetCount else {
            timeUntilNext = 0
            return
        }
        for offset in particles.indices {
            let index = (nextIndex + offset) % particles.count
            guard particles[index].isWaiting else { continue }
            particles[index] = WelcomeParticle(phase: 0)
            nextIndex = (index + 1) % particles.count
            timeUntilNext = max(0, timeUntilNext + (2.6 / speed + 1) / CGFloat(targetCount))
            return
        }
    }

    private func emitBurst() {
        for _ in 0..<5 {
            var particle = WelcomeParticle(phase: 0)
            particle.radius = .random(in: 5...50)
            particle.travel = .random(in: 0.5...1)
            particle.duration = 3
            particle.isBurst = true
            if let index = particles.firstIndex(where: { $0.isWaiting }) {
                particles[index] = particle
            } else if particles.count < Self.placements.count * 3 {
                particles.append(particle)
            }
        }
    }

    func draw(in context: CGContext, bounds: CGRect, color: UIColor, isStatic: Bool) {
        context.saveGState()
        context.translateBy(x: bounds.midX - 161, y: bounds.midY - 102)
        color.setFill()
        let count = isStatic ? Self.placements.count : particles.count
        for index in 0..<count {
            let (baseX, baseY, size, opacity) = Self.placements[index % Self.placements.count]
            let particle = particles[index]
            let progress = particle.progress
            let distance = particle.radius + 131.5 * particle.travel * progress * (1 + 3 * exp(-3 * progress))
            let x = isStatic ? baseX + size / 2 : 161 + cos(particle.angle) * distance
            let y = isStatic ? baseY + size / 2 : 112 + sin(particle.angle) * distance
            let edgeFade: CGFloat = isStatic ? 1 : max(0, min(1, min(min(x + 32, 354 - x), min(y + 32, 236 - y)) / 50))
            let scale = size / 10
            context.saveGState()
            context.translateBy(x: x, y: y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -5, y: -5)
            context.setAlpha(0.8 * min(1, isStatic ? opacity : particle.baseOpacity) * (isStatic ? 1 : particle.opacity) * edgeFade)
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
        context.restoreGState()
    }
}

private func makeWelcomeParticlePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 4.993961, y: 10.000000))
    path.addCurve(to: CGPoint(x: 4.643719, y: 9.861027), control1: CGPoint(x: 4.861111, y: 10.000000), control2: CGPoint(x: 4.744363, y: 9.953676))
    path.addCurve(to: CGPoint(x: 4.456521, y: 9.510574), control1: CGPoint(x: 4.543075, y: 9.772407), control2: CGPoint(x: 4.480676, y: 9.655589))
    path.addCurve(to: CGPoint(x: 4.130435, y: 7.927492), control1: CGPoint(x: 4.351851, y: 8.882175), control2: CGPoint(x: 4.243156, y: 8.354481))
    path.addCurve(to: CGPoint(x: 3.713768, y: 6.882175), control1: CGPoint(x: 4.017713, y: 7.500503), control2: CGPoint(x: 3.878824, y: 7.152065))
    path.addCurve(to: CGPoint(x: 3.061594, y: 6.223565), control1: CGPoint(x: 3.548711, y: 6.608258), control2: CGPoint(x: 3.331320, y: 6.388721))
    path.addCurve(to: CGPoint(x: 2.041063, y: 5.830816), control1: CGPoint(x: 2.795893, y: 6.058409), control2: CGPoint(x: 2.455717, y: 5.927492))
    path.addCurve(to: CGPoint(x: 0.501208, y: 5.546828), control1: CGPoint(x: 1.626409, y: 5.730111), control2: CGPoint(x: 1.113124, y: 5.635448))
    path.addCurve(to: CGPoint(x: 0.138889, y: 5.365559), control1: CGPoint(x: 0.356280, y: 5.526687), control2: CGPoint(x: 0.235507, y: 5.466264))
    path.addCurve(to: CGPoint(x: 0.000000, y: 4.996979), control1: CGPoint(x: 0.046296, y: 5.260826), control2: CGPoint(x: 0.000000, y: 5.137966))
    path.addCurve(to: CGPoint(x: 0.138889, y: 4.628399), control1: CGPoint(x: 0.000000, y: 4.855992), control2: CGPoint(x: 0.046296, y: 4.733132))
    path.addCurve(to: CGPoint(x: 0.507246, y: 4.447130), control1: CGPoint(x: 0.235507, y: 4.523666), control2: CGPoint(x: 0.358293, y: 4.463243))
    path.addCurve(to: CGPoint(x: 2.053140, y: 4.205438), control1: CGPoint(x: 1.119163, y: 4.378650), control2: CGPoint(x: 1.634460, y: 4.298087))
    path.addCurve(to: CGPoint(x: 3.085748, y: 3.812689), control1: CGPoint(x: 2.471819, y: 4.108761), control2: CGPoint(x: 2.816022, y: 3.977845))
    path.addCurve(to: CGPoint(x: 3.750000, y: 3.148036), control1: CGPoint(x: 3.359500, y: 3.643504), control2: CGPoint(x: 3.580918, y: 3.421953))
    path.addCurve(to: CGPoint(x: 4.160628, y: 2.084592), control1: CGPoint(x: 3.919082, y: 2.870090), control2: CGPoint(x: 4.055958, y: 2.515609))
    path.addCurve(to: CGPoint(x: 4.456521, y: 0.489426), control1: CGPoint(x: 4.265297, y: 1.649547), control2: CGPoint(x: 4.363929, y: 1.117825))
    path.addCurve(to: CGPoint(x: 4.637681, y: 0.138973), control1: CGPoint(x: 4.476650, y: 0.344411), control2: CGPoint(x: 4.537037, y: 0.227593))
    path.addCurve(to: CGPoint(x: 4.993961, y: 0.000000), control1: CGPoint(x: 4.738325, y: 0.046324), control2: CGPoint(x: 4.857085, y: 0.000000))
    path.addCurve(to: CGPoint(x: 5.356280, y: 0.138973), control1: CGPoint(x: 5.134863, y: 0.000000), control2: CGPoint(x: 5.255636, y: 0.046324))
    path.addCurve(to: CGPoint(x: 5.543478, y: 0.489426), control1: CGPoint(x: 5.456924, y: 0.227593), control2: CGPoint(x: 5.519323, y: 0.344411))
    path.addCurve(to: CGPoint(x: 5.863526, y: 2.078550), control1: CGPoint(x: 5.648148, y: 1.117825), control2: CGPoint(x: 5.754830, y: 1.647533))
    path.addCurve(to: CGPoint(x: 6.274154, y: 3.129910), control1: CGPoint(x: 5.972222, y: 2.505539), control2: CGPoint(x: 6.109098, y: 2.855992))
    path.addCurve(to: CGPoint(x: 6.932367, y: 3.782477), control1: CGPoint(x: 6.443236, y: 3.399799), control2: CGPoint(x: 6.662640, y: 3.617321))
    path.addCurve(to: CGPoint(x: 7.958937, y: 4.181269), control1: CGPoint(x: 7.202093, y: 3.947634), control2: CGPoint(x: 7.544283, y: 4.080564))
    path.addCurve(to: CGPoint(x: 9.492754, y: 4.447130), control1: CGPoint(x: 8.373591, y: 4.277945), control2: CGPoint(x: 8.884863, y: 4.366566))
    path.addCurve(to: CGPoint(x: 9.855072, y: 4.640483), control1: CGPoint(x: 9.641707, y: 4.471299), control2: CGPoint(x: 9.762479, y: 4.535750))
    path.addCurve(to: CGPoint(x: 10.000000, y: 4.996979), control1: CGPoint(x: 9.951690, y: 4.741188), control2: CGPoint(x: 10.000000, y: 4.860020))
    path.addCurve(to: CGPoint(x: 9.855072, y: 5.371601), control1: CGPoint(x: 10.000000, y: 5.141994), control2: CGPoint(x: 9.951690, y: 5.266868))
    path.addCurve(to: CGPoint(x: 9.486715, y: 5.546828), control1: CGPoint(x: 9.758454, y: 5.476334), control2: CGPoint(x: 9.635668, y: 5.534743))
    path.addCurve(to: CGPoint(x: 7.946860, y: 5.800604), control1: CGPoint(x: 8.878824, y: 5.619335), control2: CGPoint(x: 8.365539, y: 5.703927))
    path.addCurve(to: CGPoint(x: 6.908212, y: 6.187311), control1: CGPoint(x: 7.528180, y: 5.893253), control2: CGPoint(x: 7.181964, y: 6.022155))
    path.addCurve(to: CGPoint(x: 6.243961, y: 6.851964), control1: CGPoint(x: 6.634460, y: 6.352467), control2: CGPoint(x: 6.413043, y: 6.574018))
    path.addCurve(to: CGPoint(x: 5.839372, y: 7.915408), control1: CGPoint(x: 6.078905, y: 7.129910), control2: CGPoint(x: 5.944041, y: 7.484391))
    path.addCurve(to: CGPoint(x: 5.543478, y: 9.510574), control1: CGPoint(x: 5.734702, y: 8.350453), control2: CGPoint(x: 5.636070, y: 8.882175))
    path.addCurve(to: CGPoint(x: 5.362318, y: 9.861027), control1: CGPoint(x: 5.523349, y: 9.655589), control2: CGPoint(x: 5.462962, y: 9.772407))
    path.addCurve(to: CGPoint(x: 4.993961, y: 10.000000), control1: CGPoint(x: 5.261674, y: 9.953676), control2: CGPoint(x: 5.138889, y: 10.000000))
    path.closeSubpath()
    return path
}
