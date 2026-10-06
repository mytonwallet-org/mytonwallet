import Foundation

struct BlueDiamondMotion {
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0
    private(set) var scale: Float = 1
    private var previousTime: Float?
    private var animationStart: Float = 0
    private var from = SIMD2<Float>.zero
    private var target = SIMD2<Float>.zero
    private var phase = Phase.idle

    private enum Phase { case idle, tap, release, drag }

    mutating func update(time: Float) {
        let delta = min(0.1, max(0, time - (previousTime ?? time)))
        previousTime = time
        let targetScale: Float = phase == .drag ? 1.25 : 1
        scale += (targetScale - scale) * (1 - exp(-delta / 0.07))
        let elapsed = max(0, time - animationStart)
        switch phase {
        case .idle:
            yaw = from.x + 2 * .pi * (max(0, elapsed - 0.5) / 10.54).truncatingRemainder(dividingBy: 1)
        case .tap:
            let progress = min(1, elapsed / 0.22)
            let shifted = progress - 1
            let ratio = 1 + shifted * shifted * shifted * shifted * shifted
            let value = from + (target - from) * ratio
            yaw = value.x
            pitch = value.y
            if progress == 1 { release(time: time) }
        case .release:
            let progress = min(1, elapsed / 0.6)
            let shifted = progress - 1
            let ratio = -shifted * shifted * (3 * shifted + 2)
            yaw = from.x * ratio
            pitch = from.y * ratio
            if progress == 1 {
                phase = .idle
                from = .zero
                animationStart = time - 0.5
            }
        case .drag:
            break
        }
    }

    mutating func press() { phase = .drag }

    mutating func cancelInteraction(time: Float) {
        if phase == .drag { release(time: time) }
        scale = 1
        previousTime = nil
    }

    mutating func drag(dx: Float, dy: Float) {
        yaw += dx * 0.5 * .pi / 180
        pitch += dy * 0.05 * .pi / 180
    }

    mutating func release(time: Float, tap: SIMD2<Float>? = nil, tapStrength: Float = .random(in: 40...70)) {
        from = SIMD2(yaw, pitch)
        animationStart = time
        if let tap, abs(yaw) <= 10 * .pi / 180 {
            target = tap * tapStrength * .pi / 180
            phase = .tap
        } else {
            phase = .release
        }
    }
}
