import UIKit
import UIComponents

/// Telegram's audio blobs, as its `ChatRecordingBlobView` draws them: a solid circle and two smooth waves that wobble
/// and swell with the voice. The outer wave swells with the level; the inner one is the geometric mean of the circle and
/// the outer wave, so the three grow by one ratio, an evenly widening ripple.
///
/// On iOS 26 and later the waves are Telegram's liquid glass: tinted, edged with a light rim and casting a faint shadow,
/// over the content behind them refracted along each wave's edge. Before that they are the plain tint.
final class AgentVoiceBlobView: UIView {
    /// Telegram's outer wave across, silent and at the loudest, in points: its 0.627 and 1.178 of a 220 pt view
    static let outerWave: (min: CGFloat, max: CGFloat) = (138, 259)
    /// Telegram's waves are smaller while not recording and grow to their size as recording starts
    private static let restingPresence: CGFloat = 0.75
    private static let presenceInDuration: CFTimeInterval = 0.35
    /// Telegram's per-frame smoothing of the level at 60 fps
    private static let levelSmoothing: CGFloat = 0.9
    private static let centreScale = AgentVoiceRecordingMetrics.centreRestingScale
    /// How far from the centre the glass reaches: the loudest outer wave's outline, and a point for its edge
    private static let glassReach = ceil(outerWave.max / 2 * AgentVoiceBlobOutline.overshoot) + 1

    private let wavesLayer = CALayer()
    private let glass = AgentVoiceWaveGlass()
    private let outerLayer = CAShapeLayer()
    private let innerLayer = CAShapeLayer()
    private let smallLayer = CAShapeLayer()
    private var outerMotion = AgentVoiceBlobMotion()
    private var innerMotion = AgentVoiceBlobMotion()

    private var level: CGFloat = 0
    private var presentationLevel: CGFloat = 0
    private var presence: CGFloat = AgentVoiceBlobView.restingPresence
    private var presenceStart: (time: CFTimeInterval, from: CGFloat)?
    private var lastFrameTime: CFTimeInterval?
    private var isFailed = false

    /// The waves across as drawn now, before their outlines wobble
    private(set) var outerWaveDiameter: CGFloat = 0
    private(set) var innerWaveDiameter: CGFloat = 0

    var color: UIColor = .tintColor {
        didSet { applyColor() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        if let glass {
            wavesLayer.addSublayer(glass.layer)
            // Telegram's soft shadow under the outer glass wave
            outerLayer.shadowColor = UIColor.black.cgColor
            outerLayer.shadowOpacity = 0.07
            outerLayer.shadowRadius = 6
            outerLayer.shadowOffset = CGSize(width: 0, height: 2)
        }
        for wave in [outerLayer, innerLayer] {
            wave.lineWidth = 1
            wavesLayer.addSublayer(wave)
        }
        layer.addSublayer(wavesLayer)
        layer.addSublayer(smallLayer)
        applyColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wavesLayer.frame = bounds
        smallLayer.bounds = bounds
        smallLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        smallLayer.path = UIBezierPath(ovalIn: bounds).cgPath
        smallLayer.transform = CATransform3DMakeScale(Self.centreScale, Self.centreScale, 1)
        glass?.layout(center: CGPoint(x: bounds.midX, y: bounds.midY), reach: Self.glassReach)
        render()
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColor()
    }

    func updateLevel(_ level: CGFloat) {
        self.level = min(1, max(0, level))
        outerMotion.updateSpeedLevel(self.level)
        innerMotion.updateSpeedLevel(self.level)
    }

    /// Eases the drawn level toward the input level, grows the waves in and morphs them; called once per frame
    func updatePresentationLevel(at now: CFTimeInterval = CACurrentMediaTime()) {
        let elapsed = lastFrameTime.map { min(0.05, max(0, now - $0)) } ?? 1.0 / 60
        lastFrameTime = now
        let smoothing = pow(Self.levelSmoothing, CGFloat(elapsed) * 60)
        presentationLevel = presentationLevel * smoothing + level * (1 - smoothing)
        if let presenceStart {
            let progress = min(1, (now - presenceStart.time) / Self.presenceInDuration)
            presence = presenceStart.from + (1 - presenceStart.from) * easeAgentVoiceProgress(CGFloat(progress))
            if progress >= 1 { self.presenceStart = nil }
        }
        if !UIAccessibility.isReduceMotionEnabled {
            outerMotion.advance(by: CGFloat(elapsed))
            innerMotion.advance(by: CGFloat(elapsed))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        render()
        CATransaction.commit()
    }

    func startAnimating(at now: CFTimeInterval = CACurrentMediaTime()) {
        lastFrameTime = nil
        if UIAccessibility.isReduceMotionEnabled {
            presence = 1
        } else {
            presenceStart = (now, presence)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        render()
        CATransaction.commit()
    }

    func stopAnimating() {
        presentationLevel = 0
        level = 0
        presence = Self.restingPresence
        presenceStart = nil
        lastFrameTime = nil
    }

    /// Turns the centre circle red and lets the waves go, for a recording that produced no transcript
    func setFailed(_ isFailed: Bool, animated: Bool) {
        guard isFailed != self.isFailed else { return }
        self.isFailed = isFailed
        let fillColor = centreColor.cgColor
        if animated {
            let colorAnimation = CABasicAnimation(keyPath: "fillColor")
            colorAnimation.fromValue = smallLayer.presentation()?.fillColor ?? smallLayer.fillColor
            colorAnimation.toValue = fillColor
            colorAnimation.duration = 0.2
            colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            smallLayer.add(colorAnimation, forKey: "fillColor")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.2)
        wavesLayer.opacity = isFailed ? 0 : 1
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        smallLayer.fillColor = fillColor
        CATransaction.commit()
    }

    private var centreColor: UIColor {
        (isFailed ? UIColor.air.error : color).resolvedColor(with: traitCollection)
    }

    private func render() {
        guard bounds.width > 0 else { return }
        let isStill = UIAccessibility.isReduceMotionEnabled
        outerWaveDiameter = (Self.outerWave.min + (Self.outerWave.max - Self.outerWave.min) * presentationLevel) * presence
        innerWaveDiameter = (AgentVoiceRecordingMetrics.centreDiameter * outerWaveDiameter).squareRoot()
        let outer = outerMotion.makeOutline(diameter: outerWaveDiameter, isStill: isStill)
        let inner = innerMotion.makeOutline(diameter: innerWaveDiameter, isStill: isStill)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerPath = outer.makePath(around: center)
        outerLayer.path = outerPath
        innerLayer.path = inner.makePath(around: center)
        if let glass {
            outerLayer.shadowPath = outerPath
            glass.update(outlines: [outer, inner])
        }
    }

    private func applyColor() {
        let resolvedColor = color.resolvedColor(with: traitCollection)
        // Telegram's glass waves are its tint at their alpha times their fill density, edged with a light rim that is
        // fainter in the dark; its plain waves are the tint alone
        let isGlass = glass != nil
        let rimAlpha: CGFloat = traitCollection.userInterfaceStyle == .dark ? 0.3 * 0.45 : 0.3
        let rimColor = isGlass ? UIColor.white.withAlphaComponent(rimAlpha).cgColor : nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        smallLayer.fillColor = centreColor.cgColor
        outerLayer.fillColor = resolvedColor.withAlphaComponent(isGlass ? 0.35 * 0.5 : 0.15).cgColor
        innerLayer.fillColor = resolvedColor.withAlphaComponent(isGlass ? 0.55 * 0.5 : 0.3).cgColor
        outerLayer.strokeColor = rimColor
        innerLayer.strokeColor = rimColor
        CATransaction.commit()
    }
}

/// The cubic Bézier through (0.42, 0) and (0.58, 1), solved for `x` by bisection
func easeAgentVoiceProgress(_ x: CGFloat) -> CGFloat {
    func evaluateBezier(_ t: CGFloat, _ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * first + 3 * inverse * t * t * second + t * t * t
    }
    var low: CGFloat = 0
    var high: CGFloat = 1
    for _ in 0..<20 {
        let middle = (low + high) / 2
        if evaluateBezier(middle, 0.42, 0.58) < x {
            low = middle
        } else {
            high = middle
        }
    }
    return evaluateBezier((low + high) / 2, 0, 1)
}

/// A wave's outline: a closed smooth curve of eight cubic segments round its centre, in points from it
struct AgentVoiceBlobOutline {
    struct Segment {
        var start: CGPoint
        var control1: CGPoint
        var control2: CGPoint
        var end: CGPoint

        func getPoint(at t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = u * u * u
            let b = 3 * u * u * t
            let c = 3 * u * t * t
            let d = t * t * t
            return CGPoint(
                x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                y: a * start.y + b * control1.y + c * control2.y + d * end.y
            )
        }
    }

    /// How far past its nominal radius an outline can reach: its curve overshoots its points by under 5%
    static let overshoot: CGFloat = 1.05
    /// Points sampled along each segment for the outline's radii
    private static let samplesPerSegment = 32

    var segments: [Segment]

    func makePath(around center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        guard let first = segments.first else { return path }
        func translateToCenter(_ point: CGPoint) -> CGPoint { CGPoint(x: center.x + point.x, y: center.y + point.y) }
        path.move(to: translateToCenter(first.start))
        for segment in segments {
            path.addCurve(to: translateToCenter(segment.end), control1: translateToCenter(segment.control1), control2: translateToCenter(segment.control2))
        }
        path.closeSubpath()
        return path
    }

    /// The outline's distance from its centre at `count` evenly spaced angles, `atan2(y, x)` from 0 round to 2π
    func getRadii(count: Int) -> [Float] {
        var polyline: [(angle: CGFloat, radius: CGFloat)] = []
        polyline.reserveCapacity(segments.count * Self.samplesPerSegment)
        for segment in segments {
            for index in 0..<Self.samplesPerSegment {
                let point = segment.getPoint(at: CGFloat(index) / CGFloat(Self.samplesPerSegment))
                polyline.append((atan2(point.y, point.x), hypot(point.x, point.y)))
            }
        }
        guard !polyline.isEmpty, count > 0 else { return [Float](repeating: 0, count: max(0, count)) }
        let mean = polyline.reduce(0) { $0 + $1.radius } / CGFloat(polyline.count)
        var samples = [Float](repeating: Float(mean), count: count)
        let step = 2 * CGFloat.pi / CGFloat(count)
        for index in polyline.indices {
            let from = polyline[index]
            let to = polyline[(index + 1) % polyline.count]
            // The outline may run either way round; each piece covers the short way between its ends
            var span = to.angle - from.angle
            if span > .pi { span -= 2 * .pi }
            if span <= -.pi { span += 2 * .pi }
            guard span != 0 else { continue }
            let lower = min(from.angle, from.angle + span)
            let upper = max(from.angle, from.angle + span)
            var sample = Int((lower / step).rounded(.up))
            while CGFloat(sample) * step <= upper {
                let t = (CGFloat(sample) * step - from.angle) / span
                samples[((sample % count) + count) % count] = Float(from.radius + (to.radius - from.radius) * t)
                sample += 1
            }
        }
        return samples
    }
}

/// One wave's motion, as Telegram's `ChatRecordingBlobMotion`: eight points round the centre at random radii, morphing
/// to a new random shape whenever the last morph ends, faster the louder the voice was meanwhile. The curve eases from
/// one shape to the next as a shape layer's path animation would, its control points interpolated.
struct AgentVoiceBlobMotion {
    private static let pointCount = 8
    /// Handle length of the closed curve through the points: the standard cubic circle when they are evenly placed
    private static let smoothness: CGFloat = {
        let angle = 2 * CGFloat.pi / CGFloat(pointCount)
        return ((4 / 3) * tan(angle / 4)) / sin(angle / 2) / 2
    }()
    private static let minSpeed: CGFloat = 0.9
    private static let maxSpeed: CGFloat = 4
    /// Each point lies between 1 / (1 + randomness / 10) of the nominal radius and the nominal radius
    private static let randomness: CGFloat = 1
    private static let circlePoints: [CGPoint] = (0..<pointCount).map { index in
        let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(pointCount)
        return CGPoint(x: sin(angle) * 0.5, y: cos(angle) * 0.5)
    }

    /// Relative to the centre, in units of the diameter: 0.5 reaches the nominal radius
    private var fromPoints: [CGPoint]
    private var toPoints: [CGPoint] = []
    private var duration: CGFloat = 1
    private var elapsed: CGFloat = 0
    private var speedLevel: CGFloat = 0

    init() {
        fromPoints = Self.makeRandomPoints()
        startNextShape()
    }

    /// The loudest level since the current shape started decides the next one's speed
    mutating func updateSpeedLevel(_ level: CGFloat) {
        speedLevel = max(speedLevel, level)
    }

    mutating func advance(by time: CGFloat) {
        elapsed += time
        while elapsed >= duration {
            elapsed -= duration
            fromPoints = toPoints
            startNextShape()
        }
    }

    /// The outline now, `diameter` points across at its nominal radius; a still circle when `isStill`
    func makeOutline(diameter: CGFloat, isStill: Bool) -> AgentVoiceBlobOutline {
        let fromSegments = Self.makeSegments(through: isStill ? Self.circlePoints : fromPoints)
        let toSegments = isStill ? fromSegments : Self.makeSegments(through: toPoints)
        let progress = isStill ? 0 : easeAgentVoiceProgress(min(1, max(0, elapsed / duration)))
        func mix(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
            CGPoint(x: (from.x + (to.x - from.x) * progress) * diameter, y: (from.y + (to.y - from.y) * progress) * diameter)
        }
        let segments = zip(fromSegments, toSegments).map { from, to in
            AgentVoiceBlobOutline.Segment(
                start: mix(from.start, to.start),
                control1: mix(from.control1, to.control1),
                control2: mix(from.control2, to.control2),
                end: mix(from.end, to.end)
            )
        }
        return AgentVoiceBlobOutline(segments: segments)
    }

    private mutating func startNextShape() {
        toPoints = Self.makeRandomPoints()
        duration = 1 / max(0.05, Self.minSpeed + (Self.maxSpeed - Self.minSpeed) * speedLevel)
        speedLevel = 0
    }

    private static func makeRandomPoints() -> [CGPoint] {
        let angle = 2 * CGFloat.pi / CGFloat(pointCount)
        let rangeStart = 1 / (1 + randomness / 10)
        let startAngle = angle * CGFloat.random(in: 0..<1)
        return (0..<pointCount).map { index in
            let radius = (rangeStart + CGFloat.random(in: 0..<1) * (1 - rangeStart)) / 2
            let angleRandomness = angle * 0.1
            let pointAngle = angle + angle * (angleRandomness * CGFloat.random(in: 0..<1) - angleRandomness * 0.5)
            let pointAngleFromStart = startAngle + CGFloat(index) * pointAngle
            return CGPoint(x: sin(pointAngleFromStart) * radius, y: cos(pointAngleFromStart) * radius)
        }
    }

    /// The closed smooth curve through `points`: each point's handles follow the direction from its previous to its
    /// next neighbour, `smoothness` of the chord long
    private static func makeSegments(through points: [CGPoint]) -> [AgentVoiceBlobOutline.Segment] {
        func getDirection(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
            let length = hypot(to.x - from.x, to.y - from.y)
            return length > 0 ? CGPoint(x: (to.x - from.x) / length, y: (to.y - from.y) / length) : .zero
        }
        let count = points.count
        return (0..<count).map { index in
            let previous = points[(index + count - 1) % count]
            let start = points[index]
            let end = points[(index + 1) % count]
            let afterEnd = points[(index + 2) % count]
            let handle = smoothness * hypot(end.x - start.x, end.y - start.y)
            let startDirection = getDirection(previous, end)
            let endDirection = getDirection(start, afterEnd)
            return AgentVoiceBlobOutline.Segment(
                start: start,
                control1: CGPoint(x: start.x + startDirection.x * handle, y: start.y + startDirection.y * handle),
                control2: CGPoint(x: end.x - endDirection.x * handle, y: end.y - endDirection.y * handle),
                end: end
            )
        }
    }
}

/// Telegram's liquid glass under the voice waves, as its `LiquidGlassShapesLayer` draws it: the content behind the
/// waves, a little blurred, refracted along each wave's edge by a `displacementMap` filter whose map is drawn for each
/// frame. Nil before iOS 26, or where the filter or the backdrop layer is missing.
@MainActor
final class AgentVoiceWaveGlass {
    /// The glass, centred on the waves
    let layer = CALayer()
    private let backdropLayer: CALayer
    private let maskLayer = CAShapeLayer()
    private let mapLayer = CALayer()
    private var map: AgentVoiceDisplacementMap?

    private static let mapLayerName = "agentVoiceDisplacementMap"
    /// Telegram's blur of the content under the glass, captured at 1x
    private static let blurRadius: CGFloat = 1

    init?() {
        guard #available(iOS 26, *),
              let displacement = PrivateAPI.makeFilter("displacementMap"),
              let backdropLayer = PrivateAPI.makeBackdropLayer() else { return nil }
        self.backdropLayer = backdropLayer
        backdropLayer.setValue(1.0, forKey: "scale")
        backdropLayer.rasterizationScale = 1
        if let blur = WBlurredContentView.makeGaussianBlurFilter() {
            blur.setValue(Self.blurRadius, forKey: "inputRadius")
            backdropLayer.filters = [blur]
        }
        // Only the content under the waves is blurred and refracted
        backdropLayer.mask = maskLayer
        layer.addSublayer(backdropLayer)
        mapLayer.name = Self.mapLayerName
        mapLayer.zPosition = -1
        mapLayer.magnificationFilter = .linear
        layer.addSublayer(mapLayer)
        displacement.setValue(Self.mapLayerName, forKey: "inputSourceSublayerName")
        displacement.setValue(-AgentVoiceDisplacementMap.amount, forKey: "inputAmount")
        displacement.setValue(NSValue(cgPoint: CGPoint(x: 0.5, y: 0.5)), forKey: "inputOffset")
        layer.filters = [displacement]
    }

    /// Centres the glass on `center` in the waves' coordinates, reaching `reach` points from it
    func layout(center: CGPoint, reach: CGFloat) {
        layer.frame = CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)
        for sublayer in [backdropLayer, maskLayer, mapLayer] {
            sublayer.frame = layer.bounds
        }
        if map?.reach != reach {
            map = AgentVoiceDisplacementMap(reach: reach)
        }
    }

    /// Shapes the glass to the waves' `outlines` and refracts the content under their edges
    func update(outlines: [AgentVoiceBlobOutline]) {
        // Taken out while drawn, so its buffer is written in place
        guard var map else { return }
        self.map = nil
        defer { self.map = map }
        let center = CGPoint(x: map.reach, y: map.reach)
        let mask = CGMutablePath()
        for outline in outlines {
            mask.addPath(outline.makePath(around: center))
        }
        maskLayer.path = mask
        mapLayer.contents = map.makeImage(radii: outlines.map { $0.getRadii(count: AgentVoiceDisplacementMap.sampleCount) })
    }
}

/// Telegram's glass refraction as a map for the `displacementMap` filter, encoded as Telegram encodes it: red and green
/// carry the x and y offset by which content moves, 0.5 meaning none, over `amount` points. Each wave is a slab of glass
/// with a rounded edge: near its edge it shows content from further inside, most at the edge and fading out across
/// `band`.
struct AgentVoiceDisplacementMap {
    /// The outlines' radii per turn
    static let sampleCount = 256
    /// The map encodes offsets up to this many points
    static let amount: CGFloat = 32
    /// Telegram's refracting band along each edge, and how far content is pulled in at the very edge, in points
    static let band: Float = 20
    static let shift: Float = 10
    /// Pixels per point. The map is smooth except across an edge, and the content it warps is captured at 1x.
    static let scale: CGFloat = 0.5

    private struct Pixel {
        var byteOffset: Int
        /// From the centre, in points
        var distance: Float
        /// Where its angle falls among the radius samples
        var samplePosition: Float
        /// The unit vector from the centre
        var radialX: Float
        var radialY: Float
    }

    /// From the centre to the map's edges, in points
    let reach: CGFloat
    let side: Int
    /// The pixels within `reach` of the centre, nearest first
    private let pixels: [Pixel]
    private var bytes: [UInt8]
    private let pixelsPerPoint: Float

    init(reach: CGFloat) {
        self.reach = reach
        side = max(1, Int((reach * 2 * Self.scale).rounded(.up)))
        let pixelsPerPoint = CGFloat(side) / (reach * 2)
        self.pixelsPerPoint = Float(pixelsPerPoint)
        let step = 2 * CGFloat.pi / CGFloat(Self.sampleCount)
        var pixels: [Pixel] = []
        for y in 0..<side {
            for x in 0..<side {
                let pointX = (CGFloat(x) + 0.5) / pixelsPerPoint - reach
                let pointY = (CGFloat(y) + 0.5) / pixelsPerPoint - reach
                let distance = max(hypot(pointX, pointY), 0.001)
                guard distance <= reach else { continue }
                var angle = atan2(pointY, pointX)
                if angle < 0 { angle += 2 * .pi }
                pixels.append(Pixel(
                    byteOffset: (y * side + x) * 4,
                    distance: Float(distance),
                    samplePosition: Float(angle / step),
                    radialX: Float(pointX / distance),
                    radialY: Float(pointY / distance)
                ))
            }
        }
        pixels.sort { $0.distance < $1.distance }
        self.pixels = pixels
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = Self.encode(0)
            bytes[index + 1] = Self.encode(0)
            bytes[index + 2] = 255
            bytes[index + 3] = 255
        }
        self.bytes = bytes
    }

    /// The map for outlines of the given radii, each `sampleCount` of them round from `atan2(y, x)` = 0
    mutating func makeImage(radii outlines: [[Float]]) -> CGImage? {
        let pixels = self.pixels
        let count = pixels.count
        let band = Self.band
        let shift = Self.shift
        let pixelsPerPoint = self.pixelsPerPoint
        let sampleCount = Self.sampleCount
        let step = Float(2 * Double.pi) / Float(sampleCount)
        var offsetsX = [Float](repeating: 0, count: count)
        var offsetsY = [Float](repeating: 0, count: count)
        // Taken out while drawn, so the buffer is written in place
        var bytes = self.bytes
        self.bytes = []
        pixels.withUnsafeBufferPointer { pixels in
            offsetsX.withUnsafeMutableBufferPointer { offsetsX in
                offsetsY.withUnsafeMutableBufferPointer { offsetsY in
                    for outline in outlines where outline.count == sampleCount {
                        outline.withUnsafeBufferPointer { radii in
                            var lowest = radii[0]
                            var highest = radii[0]
                            for sample in 1..<sampleCount {
                                if radii[sample] < lowest { lowest = radii[sample] }
                                if radii[sample] > highest { highest = radii[sample] }
                            }
                            // Only pixels across the band inside the edge, or just outside it, are moved
                            let lower = lowest - band - 2
                            let upper = highest + 2
                            var low = 0
                            var high = count
                            while low < high {
                                let middle = (low + high) / 2
                                if pixels[middle].distance < lower { low = middle + 1 } else { high = middle }
                            }
                            var index = low
                            while index < count {
                                let pixel = pixels[index]
                                if pixel.distance > upper { break }
                                var sample = Int(pixel.samplePosition)
                                if sample >= sampleCount { sample = sampleCount - 1 }
                                let t = pixel.samplePosition - Float(sample)
                                let r0 = radii[sample]
                                let r1 = radii[sample + 1 == sampleCount ? 0 : sample + 1]
                                // For the outline r(angle), the distance to the edge is (r - |p|) / sqrt(1 + (r' / |p|)^2),
                                // and the normal into the shape is -radial + (r' / |p|) * tangential, normalized alike
                                let tangentialSlope = (r1 - r0) / step / pixel.distance
                                let normalization = 1 / (1 + tangentialSlope * tangentialSlope).squareRoot()
                                let distance = (r0 + (r1 - r0) * t - pixel.distance) * normalization
                                var coverage = distance * pixelsPerPoint + 0.5
                                if coverage > 1 { coverage = 1 }
                                let depth = distance > 0 ? distance / band : 0
                                if coverage > 0, depth < 1 {
                                    let falloff = 1 - depth
                                    let pull = shift * falloff * falloff * coverage
                                    let normalX = (-pixel.radialX - tangentialSlope * pixel.radialY) * normalization
                                    let normalY = (-pixel.radialY + tangentialSlope * pixel.radialX) * normalization
                                    offsetsX[index] += normalX * pull
                                    offsetsY[index] += normalY * pull
                                }
                                index += 1
                            }
                        }
                    }
                    bytes.withUnsafeMutableBufferPointer { bytes in
                        for index in 0..<count {
                            let offset = pixels[index].byteOffset
                            bytes[offset] = Self.encode(offsetsX[index])
                            bytes[offset + 1] = Self.encode(offsetsY[index])
                        }
                    }
                }
            }
        }
        self.bytes = bytes
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// The red and green of the pixel under `point`, in the map's points
    func encodeOffset(at point: CGPoint) -> (red: UInt8, green: UInt8) {
        let ratio = CGFloat(side) / (reach * 2)
        let x = min(side - 1, max(0, Int(point.x * ratio)))
        let y = min(side - 1, max(0, Int(point.y * ratio)))
        let offset = (y * side + x) * 4
        return (bytes[offset], bytes[offset + 1])
    }

    /// Content sampled from `offset` points away moves the opposite way, so the map carries its negation
    private static func encode(_ offset: Float) -> UInt8 {
        var value = 0.5 - 0.5 * offset / Float(amount)
        if value < 0 { value = 0 }
        if value > 1 { value = 1 }
        return UInt8(value * 255 + 0.5)
    }
}
