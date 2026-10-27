// Ported from Telegram-iOS f1dd7a2dbd; MetalKit replaces the shared MetalEngine host.
import UIKit
import CoreText
import Metal
import MetalKit
import QuartzCore

@MainActor private final class TelegramAmountMetal {
    static let shared = TelegramAmountMetal()

    struct Quad {
        var rect: SIMD4<Float>
        var color: SIMD4<Float>
        var uv: SIMD4<Float>
        var viewport: SIMD2<Float>
        var effect: SIMD2<Float>
        var reveal: SIMD2<Float>
    }
    struct Blur {
        var radius: UInt32
        var horizontal: UInt32
    }
    let device: MTLDevice
    let paint: MTLRenderPipelineState
    let maskPaint: MTLRenderPipelineState
    let blur: MTLComputePipelineState
    private var cachedAtlas: (key: TelegramAmountGlyphAtlas.Key, atlas: TelegramAmountGlyphAtlas)?

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertex = library.makeFunction(name: "walletAmountVertex"),
              let fragment = library.makeFunction(name: "walletAmountFragment"),
              let blurFunction = library.makeFunction(name: "walletAmountBlur"),
              let blur = try? device.makeComputePipelineState(function: blurFunction) else { return nil }
        func pipeline(_ format: MTLPixelFormat) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = format
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let paint = pipeline(.bgra8Unorm), let maskPaint = pipeline(.r16Float) else { return nil }
        self.device = device
        self.paint = paint
        self.maskPaint = maskPaint
        self.blur = blur
    }

    func atlas(for key: TelegramAmountGlyphAtlas.Key) -> TelegramAmountGlyphAtlas? {
        if let cachedAtlas, cachedAtlas.key == key { return cachedAtlas.atlas }
        guard let atlas = TelegramAmountGlyphAtlas(device: device, key: key) else { return nil }
        cachedAtlas = (key, atlas)
        return atlas
    }

    func quad(rect: CGRect, uv: SIMD4<Float>, color: SIMD4<Float>, viewport: CGSize, threshold: Float = -1, reveal: SIMD2<Float> = .zero) -> Quad {
        return Quad(rect: SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height)),
                    color: color, uv: uv, viewport: SIMD2(Float(viewport.width), Float(viewport.height)), effect: SIMD2(threshold, 0), reveal: reveal)
    }

    func draw(_ texture: MTLTexture, rect: CGRect, uv: SIMD4<Float>, color: SIMD4<Float>, viewport: CGSize,
              encoder: MTLRenderCommandEncoder) {
        draw(texture, quads: [quad(rect: rect, uv: uv, color: color, viewport: viewport)], encoder: encoder)
    }

    func draw(_ texture: MTLTexture, quads: [Quad], encoder: MTLRenderCommandEncoder) {
        guard !quads.isEmpty else { return }
        quads.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            encoder.setVertexBytes(base, length: buffer.count * MemoryLayout<Quad>.stride, index: 0)
        }
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: quads.count)
    }
}

final class TelegramAmountCanvas: MTKView, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue?
    private let inFlight = DispatchSemaphore(value: 2)
    private var glyphAtlas: TelegramAmountGlyphAtlas?
    private var previousGlyphAtlases: [TelegramAmountGlyphAtlas] = []
    private var atlasKey: TelegramAmountGlyphAtlas.Key?
    private var sprites: [TelegramAmountSprite] = []
    private let reveal = SIMD2<Float>.zero
    var frameDuration: Double = 1.0 / 120.0
    private(set) var hasFrame = false
    private(set) var frameGeneration = 0
    var onRenderFailure: (() -> Void)?
    var isAvailable: Bool { renderer != nil && commandQueue != nil && glyphAtlas != nil }

    init() {
        commandQueue = TelegramAmountMetal.shared?.device.makeCommandQueue()
        super.init(frame: .zero, device: TelegramAmountMetal.shared?.device)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        isPaused = true
        enableSetNeedsDisplay = false
        presentsWithTransaction = true
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func prepareGlyphs(_ glyphs: [TelegramAmountGlyph]) {
        var characters: [UIFont: String] = [:]
        for glyph in glyphs { characters[glyph.font, default: "0123456789.,"] += glyph.text }
        let unsorted: [TelegramAmountGlyphAtlas.FontCharacters] = characters.map {
            TelegramAmountGlyphAtlas.FontCharacters(font: $0.key, characters: $0.value)
        }
        let fonts = unsorted.sorted { lhs, rhs in
            if lhs.font.fontName == rhs.font.fontName { return lhs.font.pointSize < rhs.font.pointSize }
            return lhs.font.fontName < rhs.font.fontName
        }
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let key = TelegramAmountGlyphAtlas.Key(scale: scale, fonts: fonts)
        guard atlasKey != key else { return }
        if let previous = glyphAtlas { previousGlyphAtlases.append(previous) }
        glyphAtlas = renderer?.atlas(for: key)
        atlasKey = key
    }

    func update(sprites: [TelegramAmountSprite], isAnimating: Bool) {
        self.sprites = sprites
        if !isAnimating { previousGlyphAtlases.removeAll() }
        draw()
    }

    func finishMotion() {
        previousGlyphAtlases.removeAll()
        hasFrame = false
        frameGeneration &+= 1
    }

    func renderingFailed(for generation: Int) {
        // A late completion must not discard a newer frame or transition.
        guard generation == frameGeneration else { return }
        hasFrame = false
        onRenderFailure?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { releaseScratchTextures() }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let renderer, let glyphAtlas, window != nil, !bounds.isEmpty,
              UIApplication.shared.applicationState == .active,
              inFlight.wait(timeout: .now()) == .success else { return }
        guard let command = commandQueue?.makeCommandBuffer(),
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable else {
            inFlight.signal()
            return
        }
        let scale = contentScaleFactor
        let viewport = bounds.size
        let atlases = [glyphAtlas] + previousGlyphAtlases
        textureUses.removeAll(keepingCapacity: true)
        if texturePool.count > 64 { texturePool.removeAll(keepingCapacity: true) }
        var batches: [Batch] = []
        func append(_ draw: Draw) {
            let quad = renderer.quad(rect: draw.rect, uv: draw.uv, color: draw.color,
                viewport: viewport, threshold: draw.threshold, reveal: reveal)
            if let last = batches.indices.last, batches[last].texture === draw.texture,
               (batches[last].quads.count + 1) * MemoryLayout<TelegramAmountMetal.Quad>.stride <= 4096 {
                batches[last].quads.append(quad)
            } else {
                batches.append(Batch(texture: draw.texture, quads: [quad]))
            }
        }
        for sprite in sprites where sprite.alpha > 0.006 {
            if let morph = sprite.morph,
               let draw = melt(sprite, morph: morph, atlases: atlases, scale: scale, command: command) {
                append(draw)
            } else {
                for draw in draws(sprite, atlases: atlases, frameDuration: frameDuration) { append(draw) }
            }
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        encoder.setRenderPipelineState(renderer.paint)
        for batch in batches { renderer.draw(batch.texture, quads: batch.quads, encoder: encoder) }
        encoder.endEncoding()
        frameGeneration &+= 1
        let generation = frameGeneration
        command.addCompletedHandler { [weak self, inFlight] command in
            inFlight.signal()
            guard command.status == .error else { return }
            DispatchQueue.main.async { [weak self] in
                self?.renderingFailed(for: generation)
            }
        }
        command.commit()
        // Present with the UIKit visibility changes in the same Core Animation
        // transaction, so the incoming native text never overlaps the animation.
        command.waitUntilScheduled()
        guard command.status != .error else {
            renderingFailed(for: generation)
            return
        }
        drawable.present()
        hasFrame = true
    }
    private struct Batch {
        let texture: MTLTexture
        var quads: [TelegramAmountMetal.Quad]
    }
    private struct TexturePair {
        let mask: MTLTexture
        let temporary: MTLTexture
    }
    private struct Draw {
        let texture: MTLTexture
        let rect: CGRect
        let color: SIMD4<Float>
        var uv: SIMD4<Float> = SIMD4(0, 0, 1, 1)
        var threshold: Float = -1
    }
    private let renderer = TelegramAmountMetal.shared
    private var texturePool: [String: [TexturePair]] = [:]
    private var textureUses: [String: Int] = [:]
    func releaseScratchTextures() {
        texturePool.removeAll()
    }

    private func textures(width: Int, height: Int) -> TexturePair? {
        guard let renderer else { return nil }
        let key = "\(width)x\(height)"
        let index = textureUses[key, default: 0]
        textureUses[key] = index + 1
        if let pool = texturePool[key], index < pool.count { return pool[index] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let mask = renderer.device.makeTexture(descriptor: descriptor),
              let temporary = renderer.device.makeTexture(descriptor: descriptor) else { return nil }
        let pair = TexturePair(mask: mask, temporary: temporary)
        texturePool[key, default: []].append(pair)
        return pair
    }

    private func color(_ color: UIColor, alpha: CGFloat) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a * alpha))
    }

    private func mask(for glyph: TelegramAmountGlyph, atlases: [TelegramAmountGlyphAtlas]) -> TelegramAmountGlyphAtlas.Mask? {
        for atlas in atlases {
            if let mask = atlas.mask(for: glyph) { return mask }
        }
        return nil
    }

    private func melt(_ sprite: TelegramAmountSprite, morph: TelegramAmountMorph,
                      atlases: [TelegramAmountGlyphAtlas], scale: CGFloat, command: MTLCommandBuffer) -> Draw? {
        guard let renderer,
              let old = mask(for: morph.from, atlases: atlases),
              let new = mask(for: sprite.glyph, atlases: atlases) else { return nil }
        let p = min(1, max(0, morph.progress))
        let radius = morph.from.font.capHeight * 0.19 * pow(max(0, sin(.pi * p)), 0.55)
        let sxOld = 1 + 0.08 * p, syOld = 1 - 0.22 * p
        let sxNew = 1.08 - 0.08 * p, syNew = 0.78 + 0.22 * p
        let oldRect = old.rect.applying(CGAffineTransform(scaleX: sxOld, y: syOld))
        let newRect = new.rect.applying(CGAffineTransform(scaleX: sxNew, y: syNew))
        let padding = max(morph.from.font.capHeight, sprite.glyph.font.capHeight)
        let union = old.rect.union(new.rect).insetBy(dx: -padding, dy: -padding)
        let width = max(1, Int(ceil(union.width * scale)))
        let height = max(1, Int(ceil(union.height * scale)))
        let size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        guard let pair = textures(width: width, height: height) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = pair.mask
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(renderer.maskPaint)
        renderer.draw(old.texture, rect: oldRect.offsetBy(dx: -union.minX, dy: -union.minY), uv: old.uv,
            color: SIMD4(1, 1, 1, Float(pow(1 - p, 0.55))), viewport: size, encoder: encoder)
        renderer.draw(new.texture, rect: newRect.offsetBy(dx: -union.minX, dy: -union.minY), uv: new.uv,
            color: SIMD4(1, 1, 1, Float(pow(p, 0.55))), viewport: size, encoder: encoder)
        encoder.endEncoding()

        let sigma = max(Float(radius * scale), 0.01)
        let kernelRadius = Int(ceil(sigma * 3))
        var weights = (-kernelRadius ... kernelRadius).map { offset in
            exp(-Float(offset * offset) / (2 * sigma * sigma))
        }
        let weightSum = weights.reduce(0, +)
        for i in weights.indices { weights[i] /= weightSum }
        for horizontal in [true, false] {
            guard let compute = command.makeComputeCommandEncoder() else { return nil }
            compute.setComputePipelineState(renderer.blur)
            compute.setTexture(horizontal ? pair.mask : pair.temporary, index: 0)
            compute.setTexture(horizontal ? pair.temporary : pair.mask, index: 1)
            var blur = TelegramAmountMetal.Blur(radius: UInt32(kernelRadius), horizontal: horizontal ? 1 : 0)
            compute.setBytes(&blur, length: MemoryLayout<TelegramAmountMetal.Blur>.stride, index: 0)
            weights.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    compute.setBytes(base, length: buffer.count * MemoryLayout<Float>.stride, index: 1)
                }
            }
            compute.dispatchThreadgroups(MTLSize(width: (width + 7) / 8, height: (height + 7) / 8, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            compute.endEncoding()
        }
        return Draw(texture: pair.mask,
                    rect: CGRect(origin: CGPoint(x: sprite.glyph.position.x + union.minX, y: sprite.glyph.position.y + union.minY), size: size),
                    color: color(sprite.glyph.color, alpha: sprite.alpha), threshold: 0.42)
    }

    private func draws(_ sprite: TelegramAmountSprite, atlases: [TelegramAmountGlyphAtlas], frameDuration: Double) -> [Draw] {
        guard let mask = mask(for: sprite.glyph, atlases: atlases) else { return [] }
        let glyph = sprite.glyph
        let pitch = glyph.font.capHeight * 0.8
        let vertical = min(abs(sprite.travel.y), pitch * 1.4)
        let travel = max(vertical, abs(sprite.travel.x))
        let haze = max(sprite.spread, sprite.spread - sprite.spreadTravel)
        let moving = travel > 0.01
        let span = max(travel, haze, moving ? sprite.soft : 0)
        let density = min(1, (1.0 / 90) / max(frameDuration, 1.0 / 120))
        let samples = span > 1 ? max(3, Int(Double(min(2 + Int(span), 18)) * density)) : 1
        let weights = (0 ..< samples).map { i -> CGFloat in
            let k = samples > 1 ? CGFloat(i) / CGFloat(samples - 1) * 2 - 1 : 0
            return 1 - 0.55 * k * k
        }
        let total = weights.reduce(0, +)
        let stretch = moving ? max(min(span, pitch * 1.4) / travel, 1) : 1
        let zoom = moving ? 0 : span / max(glyph.width, 1)
        var result: [Draw] = []
        for sample in 0 ..< samples {
            let alpha = sprite.alpha * weights[sample] / total
            guard alpha > 0.008 else { continue }
            let k = samples > 1 ? CGFloat(sample) / CGFloat(samples - 1) : 1
            let dx = sprite.travel.x * (k - 1) * stretch
                + (k - 0.5) * (sprite.spread + (k - 1) * sprite.spreadTravel)
            let dy = sprite.travel.y * (k - 1) * stretch
            let s = sprite.scale + (k - 1) * sprite.scaleTravel + (k - 0.5) * zoom
            let cap = sprite.scalesFromBaseline ? 0 : glyph.font.capHeight / 2
            let rect = CGRect(x: glyph.position.x + dx + mask.rect.minX * s,
                              y: glyph.position.y + dy - cap + (mask.rect.minY + cap) * s,
                              width: mask.rect.width * s, height: mask.rect.height * s)
            result.append(Draw(texture: mask.texture, rect: rect, color: color(glyph.color, alpha: alpha), uv: mask.uv))
        }
        return result
    }

}

@MainActor final class TelegramAmountGlyphAtlas {
    struct FontCharacters: Hashable {
        let font: UIFont
        let characters: String

        init(font: UIFont, characters: String) {
            self.font = font
            self.characters = String(Set(characters).sorted())
        }
    }

    struct Key: Hashable {
        let scale: CGFloat
        let fonts: [FontCharacters]

        init(scale: CGFloat, fonts: [FontCharacters]) {
            self.scale = scale
            self.fonts = fonts
        }


    }

    struct Mask {
        let texture: MTLTexture
        let rect: CGRect
        let uv: SIMD4<Float>
    }

    private struct GlyphKey: Hashable {
        let text: String
        let font: UIFont
    }

    private struct Outline {
        let key: GlyphKey
        let path: CGPath
        let rect: CGRect
        let width: Int
        let height: Int
        var x: Int = 0
        var y: Int = 0
    }

    private let masks: [GlyphKey: Mask]

    init?(device: MTLDevice, key: Key) {
        let scale = key.scale
        var outlines: [Outline] = []
        for fontCharacters in key.fonts {
            let font = fontCharacters.font
            for character in fontCharacters.characters {
                let text = String(character)
                let width = TelegramAmountGlyphMetrics.width(text, font: font)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
                let path = CGMutablePath()
                for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                    let count = CTRunGetGlyphCount(run)
                    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                    var indices = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    CTRunGetGlyphs(run, CFRangeMake(0, count), &indices)
                    CTRunGetPositions(run, CFRangeMake(0, count), &positions)
                    for i in 0 ..< count {
                        if let outline = CTFontCreatePathForGlyph(runFont, indices[i], nil) {
                            path.addPath(outline, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                tx: positions[i].x - width / 2, ty: -positions[i].y))
                        }
                    }
                }
                guard !path.isEmpty else { continue }
                let ink = path.boundingBoxOfPath.insetBy(dx: -2 / scale, dy: -2 / scale)
                let rect = CGRect(x: floor(ink.minX * scale) / scale, y: floor(ink.minY * scale) / scale,
                                  width: ceil(ink.width * scale + 1) / scale, height: ceil(ink.height * scale + 1) / scale)
                outlines.append(Outline(key: GlyphKey(text: text, font: font), path: path, rect: rect,
                    width: max(1, Int(round(rect.width * scale))), height: max(1, Int(round(rect.height * scale)))))
            }
        }

        outlines.sort { $0.height > $1.height }
        let gutter = 2
        let area = outlines.reduce(0) { $0 + ($1.width + gutter) * ($1.height + gutter) }
        let widest = outlines.map { $0.width + 2 * gutter }.max() ?? 1
        var width = 256
        while width * width < area || width < widest { width *= 2 }
        var x = gutter, y = gutter, rowHeight = 0
        for i in outlines.indices {
            if x + outlines[i].width + gutter > width {
                x = gutter
                y += rowHeight + gutter
                rowHeight = 0
            }
            outlines[i].x = x
            outlines[i].y = y
            x += outlines[i].width + gutter
            rowHeight = max(rowHeight, outlines[i].height)
        }
        let height = ((y + rowHeight + gutter + 15) / 16) * 16
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(gray: 1, alpha: 1)
            for outline in outlines {
                context.saveGState()
                context.translateBy(x: CGFloat(outline.x), y: CGFloat(outline.y))
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -outline.rect.minX, y: -outline.rect.minY)
                context.addPath(outline.path)
                context.fillPath()
                context.restoreGState()
            }
            return true
        }
        guard drawn else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Wallet send glyph atlas"
        bytes.withUnsafeBytes { storage in
            if let base = storage.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: width)
            }
        }
        var masks: [GlyphKey: Mask] = [:]
        for outline in outlines {
            masks[outline.key] = Mask(texture: texture, rect: outline.rect, uv: SIMD4(
                Float(outline.x) / Float(width), Float(outline.y) / Float(height),
                Float(outline.width) / Float(width), Float(outline.height) / Float(height)))
        }
        self.masks = masks
    }

    func mask(for glyph: TelegramAmountGlyph) -> Mask? {
        return masks[GlyphKey(text: glyph.text, font: glyph.font)]
    }
}
