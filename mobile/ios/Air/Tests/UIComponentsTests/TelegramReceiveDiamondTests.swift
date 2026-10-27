import MetalKit
import Testing
import UIKit
import WalletContext
import WalletCore
@testable import UIComponents

@Suite("Telegram receive diamond")
struct TelegramReceiveDiamondTests {
    @Test @MainActor func headerRefractionKeepsSnapshotTopAndBottomAligned() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            UIColor.red.setFill()
            context.fill(CGRect(x: 4, y: 1, width: 2, height: 2))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 4, y: 7, width: 2, height: 2))
        }
        let texture = try #require(DiamondForegroundTexture.make(image: image, device: device))
        var pixels = [UInt8](repeating: 0, count: 400)
        texture.getBytes(&pixels, bytesPerRow: 40, from: MTLRegionMake2D(0, 0, 10, 10), mipmapLevel: 0)
        #expect(pixels[1 * 40 + 4 * 4 + 2] > 250)
        #expect(pixels[7 * 40 + 4 * 4] > 250)
    }

    @Test @MainActor func headerRefractionPreservesTextAndClearsLightAndDarkBackgrounds() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        for dark in [false, true] {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 4), format: format).image { context in
                UIColor(white: dark ? 0.1 : 0.95, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 20, height: 4))
                (dark ? UIColor.white : UIColor.black).setFill()
                context.fill(CGRect(x: 8, y: 0, width: 2, height: 4))
                UIColor.red.setFill()
                context.fill(CGRect(x: 12, y: 0, width: 2, height: 4))
            }
            let texture = try #require(DiamondForegroundTexture.make(image: image, device: device))
            var pixels = [UInt8](repeating: 0, count: 20 * 4 * 4)
            texture.getBytes(&pixels, bytesPerRow: 80, from: MTLRegionMake2D(0, 0, 20, 4), mipmapLevel: 0)
            #expect(pixels[3] == 0)
            #expect(pixels[8 * 4 + 3] > 250)
            #expect(pixels[8 * 4] == (dark ? 255 : 0))
            #expect(pixels[12 * 4 + 2] > 250)
            #expect(pixels[12 * 4] == 0 && pixels[12 * 4 + 1] == 0)
            #expect(pixels[12 * 4 + 3] > 250)
        }
    }

    @Test @MainActor func heroClaimsOnlyItsCenterAndDisablesHiddenPlayback() throws {
        let hero = TelegramDiamondContainerView(size: 80)
        let window = showInWindow(hero)
        defer { window.isHidden = true }
        hero.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        hero.layoutIfNeeded()
        hero.configure(active: true)
        let diamond = try #require(hero.hitTest(CGPoint(x: 40, y: 40), with: nil) as? TelegramDiamondMetalView)
        #expect(diamond.accessibilityLabel == lang("3D Gram Diamond"))
        #expect(diamond.accessibilityHint == lang("Hold to enlarge. Drag to rotate."))
        #expect(hero.hitTest(CGPoint(x: -40, y: 40), with: nil) == nil)
        hero.configure(active: false)
        #expect(hero.hitTest(CGPoint(x: 40, y: 40), with: nil) == nil)
        #expect(diamond.isPaused)
    }

    @Test @MainActor func expandedHeroDrawsAboveNavigationWithoutMovingItsTouchView() throws {
        let content = UIViewController()
        let navigation = UINavigationController(rootViewController: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true }
        let hero = TelegramDiamondContainerView(size: 80)
        content.view.addSubview(hero)
        hero.frame = CGRect(x: 155, y: 110, width: 80, height: 80)
        window.layoutIfNeeded()
        hero.layoutIfNeeded()
        hero.configure(active: true)
        let center = CGPoint(x: 40, y: 40)
        let diamond = try #require(hero.hitTest(center, with: nil) as? TelegramDiamondMetalView)

        diamond.setHolding(true, at: CACurrentMediaTime())
        let surface = try #require(navigation.view.subviews.last as? MTKView)
        #expect(surface !== diamond)
        #expect(diamond.superview === hero)
        #expect(hero.hitTest(center, with: nil) === diamond)
        #expect(!surface.isUserInteractionEnabled)
        #expect(surface.accessibilityElementsHidden)
        #expect(surface.frame == diamond.convert(diamond.bounds, to: navigation.view))
        #expect(diamond.isPaused && !surface.isPaused)
        #expect(diamond.alpha == 1)
        #expect(diamond.layer.mask != nil)

        hero.configure(active: false)
        #expect(surface.superview == nil)
        #expect(surface.isPaused)
        #expect(diamond.isPaused)
        #expect(diamond.layer.mask == nil)
        #expect(diamond.frame == hero.bounds)
    }

    @Test @MainActor func inactiveDrawCallbacksDoNotReconfigureAnotherSurface() throws {
        let diamond = try #require(TelegramDiamondMetalView(diamond: ()))
        let window = showInWindow(diamond)
        defer { window.isHidden = true }
        diamond.setRestingFrame(CGRect(x: 100, y: 100, width: 80, height: 80), width: 72)
        diamond.expansionHost = { [weak window] in window?.rootViewController?.view }
        diamond.configure(active: true)

        // A format outside the renderer's SDR/HDR pair makes surface access observable
        // even when the test window cannot supply a drawable.
        let untouchedFormat = MTLPixelFormat.bgra8Unorm_srgb
        diamond.colorPixelFormat = untouchedFormat
        diamond.draw(in: diamond)
        #expect(diamond.colorPixelFormat != untouchedFormat)

        diamond.setHolding(true, at: CACurrentMediaTime())
        let surface = try #require(window.rootViewController?.view.subviews.last as? MTKView)
        #expect(surface !== diamond)
        surface.colorPixelFormat = untouchedFormat
        diamond.draw(in: diamond)
        #expect(surface.colorPixelFormat == untouchedFormat)
        diamond.draw(in: surface)
        #expect(surface.colorPixelFormat != untouchedFormat)

        diamond.setHolding(false, at: CACurrentMediaTime() - 3)
        diamond.colorPixelFormat = untouchedFormat
        diamond.draw(in: surface)
        #expect(surface.superview == nil)
        #expect(diamond.colorPixelFormat == untouchedFormat)
        diamond.draw(in: diamond)
        #expect(diamond.colorPixelFormat != untouchedFormat)
        diamond.configure(active: false)
    }

    @Test @MainActor func snapshotPreparationDoesNotSkipScaleUp() throws {
        let hero = TelegramDiamondContainerView(size: 80)
        let window = showInWindow(hero)
        defer { window.isHidden = true }
        hero.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        hero.layoutIfNeeded()
        hero.configure(active: true)
        let diamond = try #require(hero.hitTest(CGPoint(x: 40, y: 40), with: nil) as? TelegramDiamondMetalView)
        diamond.onPressBegan = {
            Thread.sleep(forTimeInterval: 0.55)
        }

        #expect(diamond.accessibilityActivate())
        diamond.draw()
        #expect(diamond.grip < 0.1)
        hero.configure(active: false)
    }

    @Test @MainActor func renderAttachmentsFollowDrawableAcrossResizeAndHDRTransitions() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(DiamondRenderer(device: device))
        let queue = try #require(device.makeCommandQueue())
        let cache = DiamondRenderTargetCache()
        // Opening canvas, expanded canvas, then the small resting canvas. Include
        // old-sized drawables and format changes while earlier frames are queued.
        let frames: [(Int, Int, MTLPixelFormat)] = [
            (960, 960, .bgra8Unorm), (660, 660, .rgba16Float), (960, 960, .rgba16Float),
            (117, 117, .bgra8Unorm), (660, 660, .bgra8Unorm), (118, 118, .rgba16Float),
            (117, 118, .bgra8Unorm), (960, 960, .bgra8Unorm),
        ]
        var commands: [MTLCommandBuffer] = []
        for (width, height, format) in frames {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = .renderTarget
            let drawableTexture = try #require(device.makeTexture(descriptor: descriptor))
            let pass = try #require(cache.renderPass(resolving: drawableTexture, sampleCount: renderer.sampleCount))
            let color = try #require(pass.colorAttachments[0].texture)
            let depth = try #require(pass.depthAttachment.texture)
            #expect(color.width == width && color.height == height && color.pixelFormat == format)
            #expect(depth.width == width && depth.height == height && depth.sampleCount == renderer.sampleCount)
            if renderer.sampleCount > 1 {
                #expect(pass.colorAttachments[0].resolveTexture === drawableTexture)
            }
            let command = try #require(queue.makeCommandBuffer())
            let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
            var style = DiamondStyle()
            style.animationMode = .continuous
            style.widthPoints = 43
            style.backgroundStars = false
            renderer.encode(encoder: encoder, size: CGSize(width: width, height: height), time: 1.2,
                starBursts: [], starOffset: .zero, motion: DiamondMotion(), style: style, grow: 1,
                pixelsPerPoint: 3, reduceMotion: false, lightBackground: true, refractionSource: nil,
                refractionStrength: 0, highlightBoost: 0, colorPixelFormat: format)
            encoder.endEncoding()
            command.commit()
            commands.append(command)
        }
        cache.clear()
        for command in commands {
            command.waitUntilCompleted()
            #expect(command.status == .completed)
        }
    }

    @Test @MainActor func headerOverlayForwardsOnlyDiamondTouches() throws {
        let header = TelegramReceiveQRContainerView()
        header.frame = CGRect(x: 0, y: 0, width: 220, height: 220)
        header.configure(address: "UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ", active: true)
        header.layoutIfNeeded()
        let overlay = TelegramReceiveDiamondTouchView(frame: header.frame)
        let parent = UIView(frame: header.frame)
        parent.addSubview(header)
        parent.addSubview(overlay)
        overlay.sourceView = parent
        let window = showInWindow(parent)
        defer { window.isHidden = true }
        #expect(overlay.hitTest(CGPoint(x: 110, y: 110), with: nil) is TelegramDiamondMetalView)
        #expect(overlay.hitTest(CGPoint(x: 10, y: 10), with: nil) == nil)
        header.configure(address: header.address, active: false)
        #expect(overlay.hitTest(CGPoint(x: 110, y: 110), with: nil) == nil)
    }

    @Test @MainActor func policyChangesPauseVisibleHeroAndResumeWithoutChangingVisibility() throws {
        let hero = TelegramDiamondContainerView(size: 80)
        let window = showInWindow(hero)
        defer { window.isHidden = true }
        hero.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        hero.layoutIfNeeded()
        hero.configure(active: true)
        let diamond = try #require(hero.hitTest(CGPoint(x: 40, y: 40), with: nil) as? TelegramDiamondMetalView)
        #expect(!diamond.isPaused)
        for gate in ["lowPower", "animations", "reduceMotion"] {
            let policy = CardBackgroundMotionPolicy(requested: true, animationsEnabled: gate != "animations",
                lowPowerMode: gate == "lowPower", reduceMotion: gate == "reduceMotion",
                applicationActive: true, visible: true)
            hero.configure(active: true, animated: policy.canAnimate)
            #expect(diamond.isPaused)
            #expect(hero.hitTest(CGPoint(x: 40, y: 40), with: nil) == nil)
            #expect(!diamond.accessibilityActivate())
            #expect(diamond.accessibilityTraits == .image)
            #expect(diamond.accessibilityHint == nil)
            #expect(diamond.drawableSize.width > 0)
            hero.configure(active: true, animated: true)
            #expect(!diamond.isPaused)
            #expect(hero.hitTest(CGPoint(x: 40, y: 40), with: nil) === diamond)
        }
    }

    @Test @MainActor func receiveOverlayPassesTouchesThroughWhilePlaybackIsDisabled() throws {
        let header = TelegramReceiveQRContainerView()
        let window = showInWindow(header)
        defer { window.isHidden = true }
        header.frame = CGRect(x: 0, y: 0, width: 220, height: 220)
        header.configure(address: "UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ", active: true)
        header.layoutIfNeeded()
        let diamond = try #require(header.hitTest(CGPoint(x: 110, y: 110), with: nil) as? TelegramDiamondMetalView)
        header.configure(address: header.address, active: true, animated: false)
        #expect(diamond.isPaused)
        #expect(header.hitTest(CGPoint(x: 110, y: 110), with: nil) == nil)
        header.configure(address: header.address, active: true, animated: true)
        #expect(header.hitTest(CGPoint(x: 110, y: 110), with: nil) === diamond)
    }

    @Test @MainActor func rendererFailureRetainsOrdinaryTokenIcons() {
        #expect(TokenHeroView.showsDiamond(for: .TONCOIN, isGramWallet: true, rendererAvailable: true))
        #expect(!TokenHeroView.showsDiamond(for: .TONCOIN, isGramWallet: true, rendererAvailable: false))
        #expect(!TokenHeroView.showsDiamond(for: .TON_USDT, isGramWallet: true, rendererAvailable: true))
        #expect(!TokenHeroView.showsDiamond(for: .TONCOIN, isGramWallet: false, rendererAvailable: true))
    }

    @Test @MainActor func voiceOverUsesLocalizedDiamondNameAndHint() throws {
        try withMessageLanguage("ru") {
            let diamond = try #require(TelegramDiamondMetalView(diamond: ()))
            #expect(diamond.accessibilityLabel == "3D-бриллиант Gram")
            #expect(diamond.accessibilityHint == "Удерживайте, чтобы увеличить. Перетаскивайте, чтобы вращать.")
        }
    }

    @MainActor private func showInWindow(_ view: UIView) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        window.isHidden = false
        return window
    }

    @Test @MainActor func qrMaskKeepsBlackModulesAndTransparentWhiteGaps() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 1), format: format).image { context in
            for (x, color) in [UIColor.black, UIColor(white: 0.5, alpha: 1), UIColor.white].enumerated() {
                color.setFill()
                context.fill(CGRect(x: x, y: 0, width: 1, height: 1))
            }
        }
        let texture = try #require(TelegramDiamondMetalView.qrMaskTexture(image: image, device: device))
        var pixels = [UInt8](repeating: 0, count: 12)
        texture.getBytes(&pixels, bytesPerRow: 12, from: MTLRegionMake2D(0, 0, 3, 1), mipmapLevel: 0)
        #expect(pixels[3] == 255)
        #expect(abs(Int(pixels[7]) - 127) <= 1)
        #expect(pixels[11] == 0)
        #expect(pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 0 })
    }

    @Test @MainActor func lensPreservesFacetsInTransparentGapsAndRefractsBlackModules() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(DiamondRenderer(device: device))
        let clear = try render(renderer: renderer, format: .bgra8Unorm, maskAlpha: nil)
        let transparent = try render(renderer: renderer, format: .bgra8Unorm, maskAlpha: 0)
        let black = try render(renderer: renderer, format: .bgra8Unorm, maskAlpha: 255)
        var differences = 0
        var unchangedStone = 0
        for offset in stride(from: 0, to: clear.count, by: 4) where clear[offset + 3] > 250 {
            #expect(abs(Int(clear[offset]) - Int(transparent[offset])) <= 1)
            #expect(abs(Int(clear[offset + 1]) - Int(transparent[offset + 1])) <= 1)
            #expect(abs(Int(clear[offset + 2]) - Int(transparent[offset + 2])) <= 1)
            if Int(clear[offset]) - Int(black[offset]) > 20 { differences += 1 }
            if clear[offset] == black[offset] { unchangedStone += 1 }
        }
        #expect(differences > 100)
        #expect(unchangedStone > 0) // Native lens leaves the stone's bevel visible.
    }

    @Test @MainActor func extendedRangePipelineRetainsHighlightsAboveSDRWhite() throws {
        let renderer = try #require(MTLCreateSystemDefaultDevice().flatMap { DiamondRenderer(device: $0) })
        let bytes = try render(renderer: renderer, format: .rgba16Float, maskAlpha: nil, boost: 0.4)
        let components = bytes.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        let values = components.map { Float(Float16(bitPattern: $0)) }
        #expect(values.allSatisfy { $0.isFinite })
        #expect(values.enumerated().contains { $0.offset % 4 != 3 && $0.element > 1.01 })
    }

    @Test func centeredReleaseKeepsMomentumAndFlingDirection() {
        for direction: Float in [-1, 1] {
            var motion = DiamondMotion()
            motion.releaseTilt = 2.6
            motion.begin(at: 0)
            motion.drag(dx: 22 * direction, dy: 40, scale: 220, at: 0.1)
            motion.step(dt: 0.05, speed: 0, reduceMotion: false)
            motion.end(at: 0.1)
            motion.fling(direction: direction, impulse: 19.5)
            let initialYaw = motion.yaw
            for _ in 0..<6 { motion.step(dt: 1 / 60, speed: 0, reduceMotion: false) }
            #expect((motion.yaw - initialYaw) * direction > 1)
            for _ in 0..<180 { motion.step(dt: 1 / 60, speed: 0, reduceMotion: false) }
            #expect(abs(motion.pitch - DiamondMotion.referencePitch) < 0.001)
        }
    }

    @MainActor private func render(renderer: DiamondRenderer, format: MTLPixelFormat, maskAlpha: UInt8?, boost: Float = 0) throws -> [UInt8] {
        let side = 256
        let device = renderer.device
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: side, height: side, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let color = try #require(device.makeTexture(descriptor: descriptor))
        descriptor.textureType = .type2DMultisample
        descriptor.sampleCount = renderer.sampleCount
        descriptor.storageMode = .private
        let multisample = try #require(device.makeTexture(descriptor: descriptor))
        descriptor.pixelFormat = .depth32Float
        let depth = try #require(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = multisample
        pass.colorAttachments[0].resolveTexture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        let queue = try #require(device.makeCommandQueue())
        let command = try #require(queue.makeCommandBuffer())
        let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
        var style = DiamondStyle()
        style.animationMode = .continuous
        style.widthPoints = 43
        style.backgroundStars = false
        style.sparkles = false
        var source: InteractiveDiamondComponent.RefractionSource?
        if let maskAlpha {
            let maskDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
            maskDescriptor.storageMode = .shared
            let texture = try #require(device.makeTexture(descriptor: maskDescriptor))
            var pixel: [UInt8] = [0, 0, 0, maskAlpha]
            texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
            source = .init(texture: texture, uv: SIMD4(0, 0, 1, 1), rect: CGRect(x: -110, y: -110, width: 220, height: 220), preservesColors: true)
        }
        renderer.encode(encoder: encoder, size: CGSize(width: side, height: side), time: 1.2,
            starBursts: [], starOffset: .zero, motion: DiamondMotion(), style: style, grow: 3.75,
            pixelsPerPoint: Float(side) / 220, reduceMotion: false, lightBackground: true,
            refractionSource: source, refractionStrength: 1, highlightBoost: boost, colorPixelFormat: format)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        #expect(command.status == .completed)
        let bytesPerPixel = format == .rgba16Float ? 8 : 4
        var bytes = [UInt8](repeating: 0, count: side * side * bytesPerPixel)
        color.getBytes(&bytes, bytesPerRow: side * bytesPerPixel, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        return bytes
    }
}
