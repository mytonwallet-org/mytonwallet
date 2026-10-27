import UIKit
import WalletCore
import MetalKit
import Combine

/// An ephemeral image of the visible element is broken into textured fragments.
/// Images/buffers exist only during the transition, never in the concealed state.
@MainActor
final class CardElementTransition {
    private weak var target: UIView?
    private weak var snapshotSource: UIView?
    private var pendingRevealOrigin: CGPoint?
    private var pendingRenderFrames = 0
    private weak var dust: CardSpoilerDustView?
    private var concealed: Bool?
    private(set) var overlay: CardElementParticlesView?
    private var link: CADisplayLink?
    private var crossfade: UIViewPropertyAnimator?
    private let transitionMode: () -> HeroParticleAnimationPolicy.TransitionMode
    private var previousTime: CFTimeInterval = 0
    private var animationSettings = CardDisintegrationSettings.calm
    private(set) var progress: CGFloat = 0
    var nextOrigin: CGPoint?
    var settings = CardParticleSettings.original
    var active = false { didSet { if !active { settle() } } }
    var isAnimating: Bool { overlay != nil || crossfade != nil || pendingRevealOrigin != nil }
    private var observers: [NSObjectProtocol] = []
    private var policyObservation: AnyCancellable?

    init(transitionMode: @escaping () -> HeroParticleAnimationPolicy.TransitionMode = { HeroParticleAnimationPolicy.transitionMode }) {
        self.transitionMode = transitionMode
        policyObservation = HeroParticleAnimationPolicy.observe { [weak self] in
            guard let self else { return }
            if transitionMode() == .instant || (transitionMode() == .crossfade && isAnimating) { settle() }
        }
        for name in [UIApplication.willResignActiveNotification, UIAccessibility.reduceMotionStatusDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settle() }
            })
        }
    }
    // Older iOS concurrency runtimes can crash in isolated deinit (Swift #85663).
    // Cleanup only invalidates resources; it does not touch actor-isolated UI.
    deinit { link?.invalidate(); for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    func setConcealed(_ hidden: Bool, in target: UIView, snapshotSource: UIView, dust: CardSpoilerDustView, animated: Bool) {
        guard concealed != hidden || self.target !== target else { return }
        let wasConcealed = concealed
        self.target = target; self.snapshotSource = snapshotSource; self.dust = dust; concealed = hidden
        let origin = nextOrigin ?? CGPoint(x: target.bounds.midX, y: target.bounds.midY)
        nextOrigin = nil
        guard wasConcealed != nil, animated, active, transitionMode() != .instant,
              !UIAccessibility.isReduceMotionEnabled, target.window != nil,
              !target.bounds.isEmpty, dust.superview != nil else { settle(); return }
        if transitionMode() == .crossfade || crossfade != nil {
            fade(toConcealed: hidden, wasConcealed: wasConcealed == true, target: target, dust: dust)
            return
        }
        if pendingRevealOrigin != nil {
            // A second tap before the capture returns to the original cloud.
            settle()
            return
        }
        if overlay == nil, wasConcealed == true {
            animationSettings = settings.disintegration.clamped
            progress = animationSettings.blendEnd
            pendingRevealOrigin = origin
            // Let newly configured SwiftUI digits reach the render tree through
            // a normal frame. The visibility container stays concealed throughout.
            pendingRenderFrames = 1
            startDisplayLink()
            return
        }
        beginParticles(wasConcealed: wasConcealed == true, origin: origin)
    }

    private func beginParticles(wasConcealed: Bool, origin: CGPoint) {
        guard let target, let snapshotSource, let dust, let host = dust.superview else { settle(); return }
        let startsNewCloud = overlay == nil
        if overlay == nil {
            animationSettings = settings.disintegration.clamped
            let image = Self.capture(snapshotSource)
            let padding = max(90, animationSettings.travel * 2 + abs(animationSettings.lift) * 1.5 + 16)
            let frame = host.bounds.insetBy(dx: -padding, dy: -padding)
            let sourceRect = snapshotSource.convert(snapshotSource.bounds, to: host).offsetBy(dx: -frame.minX, dy: -frame.minY)
            let field = dust.convert(dust.fieldRect, to: host).offsetBy(dx: -frame.minX, dy: -frame.minY)
            let tap = target.convert(origin, to: host)
            let dustOrigin = dust.convert(CGPoint.zero, to: host)
            let samples = dust.transitionSamples(offset: CGPoint(x: dustOrigin.x - frame.minX, y: dustOrigin.y - frame.minY))
            guard let view = CardElementParticlesView(image: image, sourceRect: sourceRect, field: field,
                origin: CGPoint(x: tap.x - frame.minX, y: tap.y - frame.minY), settings: settings, cloudSamples: samples) else { settle(); return }
            view.frame = frame; host.addSubview(view); overlay = view
            progress = wasConcealed ? 1 : 0
        }
        if concealed == false { progress = min(progress, animationSettings.blendEnd) }
        target.isHidden = true
        dust.setConcealed(true, animated: false)
        render(resetCloudTracking: startsNewCloud)
        startDisplayLink()
    }

    private func startDisplayLink() {
        guard link == nil else { return }
        previousTime = 0
        let proxy = ElementDisplayLinkTarget(owner: self)
        let link = CADisplayLink(target: proxy, selector: #selector(ElementDisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common); self.link = link
    }
    /// Read the existing render tree without committing any screen-wide updates
    /// or briefly exposing the concealed element in the live hierarchy.
    static func capture(_ target: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(2, max(1, target.traitCollection.displayScale))
        format.opaque = false
        return UIGraphicsImageRenderer(bounds: target.bounds, format: format).image { _ in
            target.drawHierarchy(in: target.bounds, afterScreenUpdates: false)
        }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        if let origin = pendingRevealOrigin {
            if pendingRenderFrames > 0 { pendingRenderFrames -= 1; return }
            pendingRevealOrigin = nil
            beginParticles(wasConcealed: true, origin: origin)
            previousTime = link.timestamp
            return
        }
        let dt = previousTime == 0 ? 1 / 60.0 : min(0.1, max(0, link.timestamp - previousTime))
        previousTime = link.timestamp
        advance(by: dt)
    }
    func advance(by dt: TimeInterval) {
        guard overlay != nil, dt > 0 else { return }
        let duration = concealed == true ? animationSettings.hideDuration : animationSettings.revealDuration
        let speed: CGFloat = concealed == true ? 1 : -animationSettings.blendEnd
        progress = min(1, max(0, progress + CGFloat(dt) / duration * speed))
        render(elapsed: dt)
        if (concealed == true && progress == 1) || (concealed == false && progress == 0) { settle() }
    }
    private func render(elapsed: TimeInterval = 0, resetCloudTracking: Bool = false) {
        if let overlay, let dust, let host = overlay.superview {
            let ink = dust.convert(overlay.sourceInkRect, from: overlay)
            dust.setTransitionFootprint(ink, progress: progress / animationSettings.blendEnd)
            let origin = dust.convert(CGPoint.zero, to: host)
            overlay.updateCloudSamples(dust.transitionSamples(), offset:
                CGPoint(x: origin.x - overlay.frame.minX, y: origin.y - overlay.frame.minY), elapsed: elapsed, resetTracking: resetCloudTracking)
        }
        overlay?.progress = Float(progress)
        // Both directions use the same timeline, so rapid taps reverse in place.
        dust?.alpha = animationSettings.cloudOpacity(at: progress)
    }
    func reset() { settle(); concealed = nil; target = nil; snapshotSource = nil; dust = nil; nextOrigin = nil }

    private func fade(toConcealed hidden: Bool, wasConcealed: Bool, target: UIView, dust: CardSpoilerDustView) {
        pendingRevealOrigin = nil; pendingRenderFrames = 0
        let visibleOpacity: CGFloat
        if let crossfade {
            visibleOpacity = CGFloat(target.layer.presentation()?.opacity ?? Float(target.alpha))
            crossfade.stopAnimation(true)
            self.crossfade = nil
        } else {
            visibleOpacity = wasConcealed ? 0 : 1
        }
        link?.invalidate(); link = nil
        overlay?.removeFromSuperview(); overlay = nil
        dust.setConcealed(true, animated: false)
        UIView.performWithoutAnimation {
            target.isHidden = false
            target.alpha = visibleOpacity
            dust.alpha = 1 - visibleOpacity
        }
        let animator = UIViewPropertyAnimator(duration: 0.18, curve: .easeInOut) {
            target.alpha = hidden ? 0 : 1
            dust.alpha = hidden ? 1 : 0
        }
        crossfade = animator
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator, self.crossfade === animator, position == .end else { return }
            self.crossfade = nil
            self.settle()
        }
        animator.startAnimation()
    }

    private func settle() {
        dust?.setTransitionFootprint(nil)
        pendingRevealOrigin = nil; pendingRenderFrames = 0
        crossfade?.stopAnimation(true); crossfade = nil
        link?.invalidate(); link = nil; previousTime = 0
        overlay?.removeFromSuperview(); overlay = nil
        if let concealed {
            target?.alpha = 1
            target?.isHidden = concealed
            dust?.alpha = 1
            dust?.setConcealed(concealed, animated: false)
            progress = concealed ? 1 : 0
        }
    }
}

@MainActor private final class ElementDisplayLinkTarget: NSObject {
    weak var owner: CardElementTransition?
    init(owner: CardElementTransition) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

/// One instanced draw, independent of the number of fragments. The texture is
/// captured from the element, so every fragment keeps its actual original pixels.
@MainActor
final class CardElementParticlesView: MTKView, MTKViewDelegate {
    private struct Fragment {
        var source: SIMD2<Float>
        var destination: SIMD2<Float>
        var bend: SIMD2<Float>
        var size: SIMD2<Float>
        var uv: SIMD4<Float>
        var timing: SIMD4<Float>
        var cloud: SIMD4<Float>
    }
    private struct Uniforms {
        var size: SIMD2<Float>
        var progress: Float
        var particleSize: Float
        var blend: SIMD4<Float>
    }
    private final class Resources {
        static let shared = Resources()
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            do {
                let library = try device.makeDefaultLibrary(bundle: bundle)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "elementVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "elementFragment")
                let attachment = descriptor.colorAttachments[0]!
                attachment.pixelFormat = .bgra8Unorm; attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one; attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one; attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch { NSLog("Hero element particles: %@", String(describing: error)); return nil }
            self.device = device; self.queue = queue
        }
    }
    private let resources: Resources
    private let texture: MTLTexture
    private let buffers: CardParticleBufferPool
    private var fragments: [Fragment]
    private var cloudIndices: [Int]
    private struct CloudTarget {
        var sample: CardSpoilerDustView.TransitionSample
        var offset = CGPoint.zero
    }
    private var cloudTargets: [CloudTarget]
    let sourceInkRect: CGRect
    let fragmentCount: Int
    private let particleSize: Float
    private let animationSettings: CardDisintegrationSettings
    var progress: Float = 0 { didSet { setNeedsDisplay() } }

    init?(image: UIImage, sourceRect: CGRect, field: CGRect, origin: CGPoint, settings: CardParticleSettings,
          cloudSamples: [CardSpoilerDustView.TransitionSample] = []) {
        guard let resources = Resources.shared, let image = image.cgImage else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0, !field.isEmpty, !sourceRect.isEmpty,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext pixels are already premultiplied in encoded sRGB. An sRGB
        // texture/target would multiply fade opacity in linear light and encode
        // RGB above alpha, causing colored fringes in transparent compositing.
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared; desc.usage = .shaderRead
        guard let texture = resources.device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        let tuning = settings.clamped
        let motion = tuning.disintegration
        let desired = max(0.8, motion.fragmentSize / sqrt(tuning.frequency))
        let step = max(1, Int(ceil(max(desired, sqrt(sourceRect.width * sourceRect.height / 9000)) * CGFloat(width) / max(1, sourceRect.width))))
        let rgba = bytes.assumingMemoryBound(to: UInt8.self)
        var seed: UInt64 = 0xD1571A7E
        func random() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 32) / CGFloat(UInt32.max) }
        var fragments: [Fragment] = []
        var inkBounds = CGRect.null
        var cloudIndices: [Int] = []
        // A small spatial grid avoids searching every live dot for each fragment.
        struct Cell: Hashable { let x: Int; let y: Int }
        func cell(_ point: CGPoint) -> Cell { Cell(x: Int(floor(point.x / 16)), y: Int(floor(point.y / 16))) }
        var grid: [Cell: [Int]] = [:]
        var uses = Array(repeating: 0, count: cloudSamples.count)
        for (index, sample) in cloudSamples.enumerated() { grid[cell(sample.position), default: []].append(index) }
        func nearestCloud(to point: CGPoint) -> Int {
            guard !cloudSamples.isEmpty else { return -1 }
            let center = cell(point)
            var candidates: [Int] = []
            for y in -1...1 { for x in -1...1 {
                candidates += grid[Cell(x: center.x + x, y: center.y + y)] ?? []
            } }
            if candidates.isEmpty { candidates = Array(cloudSamples.indices) }
            let result = candidates.min { a, b in
                func score(_ index: Int) -> CGFloat {
                    let p = cloudSamples[index].position
                    return hypot(p.x - point.x, p.y - point.y) + CGFloat(uses[index]) * 12
                }
                return score(a) < score(b)
            }!
            uses[result] += 1
            return result
        }
        let shape = UIBezierPath(roundedRect: field, cornerRadius: field.height / 2)
        for y in stride(from: 0, to: height, by: step) { for x in stride(from: 0, to: width, by: step) {
            let tileWidth = min(step, width - x), tileHeight = min(step, height - y)
            var hasInk = false
            for py in y..<(y + tileHeight) {
                for px in x..<(x + tileWidth) where rgba[(py * width + px) * 4 + 3] > 8 { hasInk = true; break }
                if hasInk { break }
            }
            guard hasInk else { continue }
            let sx = CGFloat(x) / CGFloat(width), sy = CGFloat(y) / CGFloat(height)
            let w = CGFloat(tileWidth) / CGFloat(width), h = CGFloat(tileHeight) / CGFloat(height)
            let center = CGPoint(x: sourceRect.minX + (sx + w / 2) * sourceRect.width, y: sourceRect.minY + (sy + h / 2) * sourceRect.height)
            inkBounds = inkBounds.union(CGRect(x: sourceRect.minX + sx * sourceRect.width,
                y: sourceRect.minY + sy * sourceRect.height, width: w * sourceRect.width, height: h * sourceRect.height))
            var destination: CGPoint
            repeat { destination = CGPoint(x: field.minX + random() * field.width, y: field.minY + random() * field.height) } while !shape.contains(destination)
            // A local destination avoids crossing the whole balance by default.
            // Project onto the rounded cloud field; the shuffle knob restores the old flight.
            var local = CGPoint(x: min(field.maxX, max(field.minX, center.x)), y: min(field.maxY, max(field.minY, center.y)))
            if !shape.contains(local) {
                let radius = field.height / 2
                let cx = min(field.maxX - radius, max(field.minX + radius, local.x))
                let dx = local.x - cx, dy = local.y - field.midY
                let scale = (radius - 0.01) / max(radius, hypot(dx, dy))
                local = CGPoint(x: cx + dx * scale, y: field.midY + dy * scale)
            }
            destination = CGPoint(x: local.x + (destination.x-local.x)*motion.destinationMix,
                                  y: local.y + (destination.y-local.y)*motion.destinationMix)
            let anchor = CGPoint(x: sourceRect.midX + (origin.x-sourceRect.midX)*motion.originInfluence,
                                 y: sourceRect.midY + (origin.y-sourceRect.midY)*motion.originInfluence)
            let dx = center.x - anchor.x, dy = center.y - anchor.y, distance = max(1, hypot(dx, dy))
            let travel = motion.travel * (1 + (random()*2-1)*motion.turbulence)
            let delay = min(1, distance / max(1, hypot(sourceRect.width, sourceRect.height))) * motion.stagger + random() * motion.timingRandomness
            let cloudIndex = nearestCloud(to: destination)
            cloudIndices.append(cloudIndex)
            let sample = cloudIndex >= 0 ? cloudSamples[cloudIndex] : nil
            if let sample { destination = sample.position }
            fragments.append(Fragment(source: .init(Float(center.x), Float(center.y)), destination: .init(Float(destination.x), Float(destination.y)),
                bend: .init(Float(dx / distance * travel), Float(dy / distance * travel - motion.lift * (1 + (random()*2-1)*motion.turbulence))),
                size: .init(Float(w * sourceRect.width), Float(h * sourceRect.height)),
                uv: .init(Float(sx), Float(sy), Float(w), Float(h)),
                timing: .init(Float(delay), Float(0.6 + random() * 0.8), Float((random()*2-1) * motion.rotation * .pi / 180), Float(max(0.08, 0.98 - motion.stagger - motion.timingRandomness))),
                cloud: .init(0, 0, Float(sample?.diameter ?? 0), Float(sample?.opacity ?? -1))))
        } }
        guard !fragments.isEmpty, let buffers = CardParticleBufferPool(device: resources.device, length: fragments.count * MemoryLayout<Fragment>.stride) else { return nil }
        self.resources = resources; self.texture = texture; self.buffers = buffers; fragmentCount = fragments.count
        self.sourceInkRect = inkBounds
        self.fragments = fragments; self.cloudIndices = cloudIndices
        cloudTargets = cloudSamples.map { CloudTarget(sample: $0) }
        particleSize = Float(tuning.size * motion.finalSize)
        animationSettings = motion
        super.init(frame: .zero, device: resources.device)
        isUserInteractionEnabled = false; isAccessibilityElement = false; accessibilityElementsHidden = true
        isOpaque = false; backgroundColor = .clear; clearColor = MTLClearColorMake(0, 0, 0, 0)
        colorPixelFormat = .bgra8Unorm; framebufferOnly = true
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        isPaused = true; enableSetNeedsDisplay = true; delegate = self
        accessibilityIdentifier = "elementParticleTransition"
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func updateCloudSamples(_ samples: [CardSpoilerDustView.TransitionSample], offset: CGPoint = .zero, elapsed: TimeInterval = 0, resetTracking: Bool = false) {
        guard !samples.isEmpty else { return }
        let decay = exp(-30 * max(0, min(0.1, elapsed)))
        for index in samples.indices {
            var sample = samples[index]
            sample.position.x += offset.x; sample.position.y += offset.y
            if index >= cloudTargets.count { cloudTargets.append(CloudTarget(sample: sample)); continue }
            if resetTracking { cloudTargets[index] = CloudTarget(sample: sample); continue }
            let previous = cloudTargets[index].sample
            let dx = previous.position.x - sample.position.x, dy = previous.position.y - sample.position.y
            // A live dot wraps its drift while invisible. Its still-visible
            // fragment must bridge that wrap instead of teleporting with it.
            if hypot(dx, dy) > 8, min(previous.opacity, sample.opacity) <= 1 / 64 {
                cloudTargets[index].offset.x += dx; cloudTargets[index].offset.y += dy
            }
            cloudTargets[index].offset.x *= decay; cloudTargets[index].offset.y *= decay
            cloudTargets[index].sample = sample
        }
        for index in fragments.indices {
            guard cloudIndices[index] >= 0 else { continue }
            let target = cloudTargets[min(cloudIndices[index], samples.count - 1)]
            let sample = target.sample
            fragments[index].destination = .init(Float(sample.position.x + target.offset.x), Float(sample.position.y + target.offset.y))
            fragments[index].cloud.z = Float(sample.diameter)
            fragments[index].cloud.w = Float(sample.opacity)
        }
        setNeedsDisplay()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard window != nil, UIApplication.shared.applicationState == .active else { return }
        guard let slot = buffers.acquire() else { setNeedsDisplay(); return }
        guard let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let command = resources.queue.makeCommandBuffer() else { buffers.release(slot.index); return }
        guard encode(pass: pass, command: command, reservedSlot: slot) else { return }
        command.present(drawable); command.commit()
    }
    private func encode(pass: MTLRenderPassDescriptor, command: MTLCommandBuffer, reservedSlot: (index: Int, buffer: MTLBuffer)? = nil) -> Bool {
        guard let slot = reservedSlot ?? buffers.acquire() else { setNeedsDisplay(); return false }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { buffers.release(slot.index); return false }
        fragments.withUnsafeBytes { bytes in
            slot.buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        command.addCompletedHandler { [buffers, slotIndex = slot.index] _ in buffers.release(slotIndex) }
        var uniforms = Uniforms(size: .init(Float(max(1,bounds.width)), Float(max(1,bounds.height))), progress: progress, particleSize: particleSize,
            blend: .init(Float(animationSettings.blendStart), Float(animationSettings.blendEnd), Float(animationSettings.easing), 0))
        encoder.setRenderPipelineState(resources.pipeline)
        encoder.setVertexBuffer(slot.buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: fragmentCount)
        encoder.endEncoding()
        return true
    }
    #if DEBUG
    var cloudDestinationsForValidation: [CGPoint] {
        fragments.map { CGPoint(x: CGFloat($0.destination.x), y: CGFloat($0.destination.y)) }
    }
    func snapshotForValidation() -> UIImage? {
        let width = max(1, Int(bounds.width * 2)), height = max(1, Int(bounds.height * 2))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget]
        guard let texture = resources.device.makeTexture(descriptor: descriptor), let command = resources.queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor
        guard encode(pass: pass, command: command) else { return nil }
        command.commit(); command.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let image = CGImage(width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }
    #endif
}
