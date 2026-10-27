import CoreMotion
import UIKit
import simd

/// Input behavior is independent of the selected reflection texture.
enum CardGramReflectionMode: Int, CaseIterable, Sendable {
    case current, telegram, predictable, physical, telegramV2
    static let menuOrder: [Self] = [.current, .telegram, .telegramV2, .predictable, .physical]
    var title: String {
        switch self {
        case .current: "Текущий"
        case .telegram: "Telegram"
        case .telegramV2: "Telegram v2"
        case .predictable: "Предсказуемое"
        case .physical: "Физичное"
        }
    }
    var explanation: String {
        switch self {
        case .current: "Прежнее управление: две оси вращают блик, после паузы положение становится исходным."
        case .telegram: "Поворот от гироскопа рассчитывается как в Telegram. Начальное положение сохраняется."
        case .telegramV2: "Симметричный отклик и мягкий предел поворота вокруг диагонали. Без перекалибровки после паузы."
        case .predictable: "Влево-вправо — поворот. Вперёд-назад — перенос яркости между лепестками."
        case .physical: "Карта отражает неподвижную лампу. Направление и яркость света зависят от её положения."
        }
    }
}

struct CardGramReflectionPose: Equatable, Sendable {
    var rotation: Double = 0 // radians, counterclockwise in the material's upward Y
    var balance: Double = 0
    var energy: Double = 1
    var light = SIMD3<Float>(-0.35, 0.5, 1.4)
    var view = SIMD3<Float>(0, 0, 1)
}

/// One reference and parallel, continuously updated models allow switching modes
/// without recalibration. Only activation/input/orientation lifecycle resets it.
struct CardGramReflectionMotion {
    private var reference: simd_quatd?
    private var orientation: UIInterfaceOrientation = .unknown
    private var deviceTilt = CardDeviceTilt()
    private var previousAngle: Double?
    private var targetRotation = 0.0
    private var rotation = 0.0
    private var targetAxes = SIMD2<Double>.zero
    private var axes = SIMD2<Double>.zero
    private var targetV2 = SIMD2<Double>.zero // rotation, large-angle attenuation
    private var v2 = SIMD2<Double>.zero
    private static let lamp = simd_normalize(SIMD3<Double>(-0.35, 0.5, 1.4))
    private var targetLight = Self.lamp
    private var light = Self.lamp
    private var targetView = SIMD3<Double>(0, 0, 1)
    private var view = SIMD3<Double>(0, 0, 1)

    mutating func reset() { self = Self() }

    mutating func sample(attitude q: CMQuaternion, rotationRate: CMRotationRate,
                         orientation: UIInterfaceOrientation, by dt: TimeInterval) {
        let vector = SIMD4(q.x, q.y, q.z, q.w)
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite, vector.w.isFinite,
              simd_length_squared(vector) > 1e-10 else { return }
        let attitude = simd_normalize(simd_quatd(vector: vector))
        if reference == nil { reference = attitude }
        guard let reference else { return }
        let worldToCard = attitude.conjugate * reference
        func screen(_ v: SIMD3<Double>) -> SIMD3<Double> {
            // Upward Y in shader/card coordinates.
            switch orientation {
            case .landscapeLeft: return SIMD3(v.y, -v.x, v.z)
            case .landscapeRight: return SIMD3(-v.y, v.x, v.z)
            case .portraitUpsideDown: return SIMD3(-v.x, -v.y, v.z)
            default: return v
            }
        }
        // Exact gyro rotation model from Telegram's WalletCardBackgroundMotion,
        // commit f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838. Touch stays native to the lab.
        let direction = screen(simd_act(worldToCard, simd_normalize(SIMD3<Double>(-0.5, 0.5, 1))))
        if self.orientation != orientation {
            self.orientation = orientation
            previousAngle = nil
            targetRotation = rotation
        }
        if hypot(direction.x, direction.y) >= 0.1 {
            let angle = atan2(-direction.y, direction.x)
            if let previousAngle {
                let delta = angle - previousAngle
                targetRotation += atan2(sin(delta), cos(delta))
            }
            previousAngle = angle
        }
        // Read raw pitch/roll; discard the legacy dead-zone response and disallow idle recenter.
        _ = deviceTilt.update(attitude: q, rotationRate: rotationRate, orientation: orientation,
                              touchActive: false, lightIsSettled: false, sensitivity: 1.5, by: dt)
        targetAxes = SIMD2(tanh(Double(deviceTilt.roll) * 2.3), tanh(Double(deviceTilt.pitch) * 2.3))
        // Telegram's projected-light angle has a singularity when the lamp faces
        // the card. Its first-order response at rest is roll - pitch - twist.
        // Apply that symmetric tangent response to a relative rotation vector,
        // so no projected azimuth or branch cut enters the usual hand-held range.
        var relative = worldToCard.conjugate
        if relative.real < 0 { relative = simd_quatd(vector: -relative.vector) }
        let radius = simd_length(relative.imag)
        let angle = 2 * atan2(radius, max(0, relative.real))
        var angular = radius > 1e-9 ? relative.imag * (angle / radius) : .zero
        switch orientation {
        case .landscapeLeft: angular = SIMD3(-angular.y, angular.x, angular.z)
        case .landscapeRight: angular = SIMD3(angular.y, -angular.x, angular.z)
        case .portraitUpsideDown: angular = SIMD3(-angular.x, -angular.y, angular.z)
        default: break
        }
        // Fade far outside ordinary viewing angles, before the +/-pi quaternion
        // seam; q and -q always produce the same output. Never recenter on idle.
        let edge = min(1, max(0, (angle - 100 * .pi / 180) / (60 * .pi / 180)))
        let fade = edge * edge * (3 - 2 * edge)
        targetV2 = SIMD2((angular.y - angular.x - angular.z) * (1 - fade), fade)
        targetLight = screen(simd_act(worldToCard, Self.lamp))
        targetView = screen(simd_act(worldToCard, SIMD3<Double>(0, 0, 1)))
    }

    mutating func synthetic(tilt: CGPoint) {
        targetAxes = SIMD2(Double(tilt.x), Double(tilt.y))
        targetRotation = -Double(tilt.x) * .pi / 3
        targetV2 = SIMD2((Double(tilt.x) - Double(tilt.y)) * 0.5, 0)
        let q = simd_quatd(angle: Double(tilt.y) * 0.35, axis: SIMD3(1,0,0))
            * simd_quatd(angle: Double(tilt.x) * 0.35, axis: SIMD3(0,1,0))
        targetLight = simd_act(q.conjugate, Self.lamp)
        targetView = simd_act(q.conjugate, SIMD3(0,0,1))
    }

    mutating func advance(by dt: TimeInterval) {
        guard dt > 0 else { return }
        rotation += (targetRotation - rotation) * (1 - exp(-dt / 0.1))
        // Slow, tiny input is filtered more; deliberate travel catches up quickly.
        let error = abs(targetV2.x - v2.x)
        let response = min(1, error / (12 * .pi / 180))
        let v2Time = 0.15 - 0.08 * response
        v2 += (targetV2 - v2) * (1 - exp(-dt / v2Time))
        if simd_length(v2 - targetV2) < 1e-10 { v2 = targetV2 }
        let amount = 1 - exp(-dt / 0.12)
        axes += (targetAxes - axes) * amount
        light += (targetLight - light) * amount
        view += (targetView - view) * amount
        if abs(rotation - targetRotation) < 1e-10 { rotation = targetRotation }
        if simd_length(axes - targetAxes) < 1e-10 { axes = targetAxes }
        if simd_length(light - targetLight) < 1e-10 { light = targetLight }
        if simd_length(view - targetView) < 1e-10 { view = targetView }
    }

    func pose(mode: CardGramReflectionMode, press: SIMD3<Double>, aspect: Double,
              v2Limit: Double = 35, v2Sensitivity: Double = 1) -> CardGramReflectionPose? {
        switch mode {
        case .current: return nil
        case .telegram:
            let touchTurn = min(1, max(-1, -aspect * press.x + press.y))
            return .init(rotation: -rotation + touchTurn * .pi / 2)
        case .telegramV2:
            let limit = min(180, max(0, v2Limit)) * .pi / 180
            let sensitivity = min(2, max(0.25, v2Sensitivity))
            let touch = (-aspect * press.x + press.y) * .pi / 3
            let turn = limit > 1e-8 ? limit * tanh((v2.x + touch) * sensitivity / limit) : 0
            return .init(rotation: turn, energy: 1 - min(1, max(0, v2.y)))
        case .predictable:
            let blend = 1 - min(1, max(0, press.z))
            return .init(rotation: -(axes.x * blend + press.x) * 65 * .pi / 180,
                         balance: axes.y * blend + press.y)
        case .physical:
            let touch = simd_quatd(angle: -press.y * 0.35, axis: SIMD3(1,0,0))
                * simd_quatd(angle: press.x * 0.35, axis: SIMD3(0,1,0))
            let l = simd_act(touch.conjugate, light), v = simd_act(touch.conjugate, view)
            return .init(light: SIMD3(Float(l.x), Float(l.y), Float(l.z)),
                         view: SIMD3(Float(v.x), Float(v.y), Float(v.z)))
        }
    }
}
