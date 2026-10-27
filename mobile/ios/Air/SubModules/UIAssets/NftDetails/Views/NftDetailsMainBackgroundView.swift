import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import MetalKit
import SwiftUI
import UIComponents

struct NftDetailsBackground {
    final class View: UIView, MTKViewDelegate {
        
        private var currentModel = Model(
            pageState: .staticPage(PageModel(backgroundColor: nil, image: nil, tag: "idle")),
            isExpanded: false,
            shouldShowPreview: false,
            heroFrame: .zero
        )
        
        private var metalView: MTKView?
        private var ciContext: CIContext?
        private var commandQueue: MTLCommandQueue?
        private var deviceScale: CGFloat { max(window?.screen.scale ?? traitCollection.displayScale, 1) }
        private let colorSpace = CGColorSpaceCreateDeviceRGB()
        private var lastLayoutSizeForPrepare: CGSize = .init(width: -1, height: -1)
        private let colorResolver: NftDetailsColorResolver
        private var isLowResDrawableActive = false

        private struct PreparedRender {
            var image: CIImage?
            var isStatic = true
            var hasPreview: Bool = false
        }
        private var preparedRender = PreparedRender()
        private var loadingFadeStart: CFTimeInterval?
        private var loadingFadeImage: CIImage?
        private let loadingFadeDuration: CFTimeInterval = 0.35
        init(colorResolver: NftDetailsColorResolver) {
            self.colorResolver = colorResolver
            super.init(frame: .zero)
            setup()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setup() {
            guard let device = MTLCreateSystemDefaultDevice() else {
                assertionFailure()
                return
            }
            
            commandQueue = device.makeCommandQueue()
            ciContext = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: true,
                .workingColorSpace: colorSpace,
                .outputColorSpace: colorSpace
            ])
            
            let mtkView = MTKView(frame: bounds, device: device)
            mtkView.translatesAutoresizingMaskIntoConstraints = false
            mtkView.delegate = self
            mtkView.isPaused = false
            mtkView.enableSetNeedsDisplay = false
            mtkView.preferredFramesPerSecond = Self.idleFramesPerSecond
            mtkView.framebufferOnly = false
            mtkView.colorPixelFormat = .bgra8Unorm
            mtkView.presentsWithTransaction = true
            mtkView.autoResizeDrawable = false

            metalView = mtkView
            addSubview(mtkView)
            
            NSLayoutConstraint.activate([
                mtkView.topAnchor.constraint(equalTo: topAnchor),
                mtkView.leadingAnchor.constraint(equalTo: leadingAnchor),
                mtkView.trailingAnchor.constraint(equalTo: trailingAnchor),
                mtkView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            
            // Warm-up: pre-compile CI/Metal shaders so the first visible frame is not delayed.
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 4,
                height: 4,
                mipmapped: false
            )
            desc.usage = [.renderTarget, .shaderRead, .shaderWrite]
            if let texture = device.makeTexture(descriptor: desc), let ciContext {
                let bounds = CGRect.square(4)

                // Pass 1 — solid color.
                if let commandBuffer = commandQueue?.makeCommandBuffer() {
                    ciContext.render(solidColorImage(extent: bounds, color: nil), to: texture,
                                     commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
                    commandBuffer.commit()
                    commandBuffer.waitUntilCompleted()
                }
            }
        }
        
        // Idle frame-rate while no transition is active. The MTKView still ticks at this rate so the GPU clock, drawable IOSurfaces, and display-link phase stay engaged
        private static let idleFramesPerSecond: Int = 10
        
        // Active frame-rate during a transition. Falls back to the device max (60/120 Hz).
        private var activeFramesPerSecond: Int { window?.screen.maximumFramesPerSecond ?? screenMaximumFramesPerSecond }

        private func updatePreferredFrameRate(isTransitioning: Bool) {
            let fps = isTransitioning ? activeFramesPerSecond
                : (currentModel.hasLiveAtmosphere ? 30 : Self.idleFramesPerSecond)
            if metalView?.preferredFramesPerSecond != fps { metalView?.preferredFramesPerSecond = fps }
        }

        private func updateDrawableResolution(isLowRes: Bool, force: Bool = false) {
            guard force || isLowResDrawableActive != isLowRes else { return }

            let size = bounds.size
            guard size.width > 0, size.height > 0 else { return }

            let k = isLowRes ? 0.2 : 1.0
            isLowResDrawableActive = isLowRes
            let newSize = CGSize(width: size.width * deviceScale * k, height: size.height * deviceScale * k)
            if metalView?.drawableSize != newSize {
                metalView?.drawableSize = newSize
            }
        }
                
        func setModel(_ model: Model) {
            guard currentModel != model else { return }
            let previous = currentModel
            if !UIAccessibility.isReduceMotionEnabled,
               case .staticPage(let old) = previous.pageState,
               case .staticPage(let new) = model.pageState,
               old.tag == new.tag,
               previous.isExpanded == model.isExpanded,
               previous.shouldShowPreview == model.shouldShowPreview,
               (old.backgroundColor != new.backgroundColor || (old.image == nil && new.image != nil)) {
                loadingFadeImage = imageForCurrentFrame()
                loadingFadeStart = CACurrentMediaTime()
            } else if model.pageState.isTransitioning || previous.isExpanded != model.isExpanded {
                loadingFadeImage = nil
                loadingFadeStart = nil
            }
            if case .staticPage(let old) = previous.pageState,
               case .staticPage(let new) = model.pageState, old.tag != new.tag {
                loadingFadeImage = nil
                loadingFadeStart = nil
            }
            currentModel = model

            updatePreferredFrameRate(isTransitioning: model.pageState.isTransitioning || loadingFadeStart != nil || currentModel.isViewportMoving)
            updateDrawableResolution(isLowRes: model.preferLowResolutionRender)
            
            render()
            if previous.shouldShowPreview != model.shouldShowPreview || previous.isExpanded != model.isExpanded
                || previous.contentOffsetY != model.contentOffsetY || previous.shouldShowAtmosphere != model.shouldShowAtmosphere
                || previous.heroFrame != model.heroFrame {
                // Hand the artwork between the Metal backdrop and the moving
                // preview in this frame, not at the next idle (10 Hz) tick.
                metalView?.draw()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            
            let size = bounds.size
            if size != lastLayoutSizeForPrepare {
                lastLayoutSizeForPrepare = size
                loadingFadeStart = nil
                loadingFadeImage = nil
                updatePreferredFrameRate(isTransitioning: currentModel.pageState.isTransitioning || currentModel.isViewportMoving)
                updateDrawableResolution(isLowRes: currentModel.preferLowResolutionRender, force: true)
                render()
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            metalView?.isPaused = (window == nil)
        }
        
        private func solidColorImage(extent: CGRect, color: UIColor?) -> CIImage {
            let uiColor = color ?? colorResolver.fallbackColor
            return CIImage(color: CIColor(cgColor: uiColor.cgColor)).cropped(to: extent)
        }
                
        private var artworkFrame: CGRect {
            NftDetailsHeroLayout.scrolledFrame(currentModel.heroFrame, offsetY: currentModel.contentOffsetY)
        }

        private func prepareSideImage(for page: PageModel, extent: CGRect, shouldShowPreview: Bool) -> CIImage {
            var result: CIImage
            result = solidColorImage(extent: extent, color: page.backgroundColor)
            if shouldShowPreview, let image = page.image {
                result = scaleToWidthAlignToTop(image, extent: extent).composited(over: result)
            }
            if currentModel.shouldShowAtmosphere, let image = page.atmosphereImage, bounds.width > 0 {
                let scale = extent.width / bounds.width
                let artwork = artworkFrame
                let artworkScale = artwork.width / max(1, currentModel.heroFrame.width)
                let overlap = NftDetailsImageProcessor.atmosphereOverlap
                let source = image.extent
                let split = source.height * page.atmosphereHeight / (page.atmosphereHeight + overlap)
                let artworkBottom = artwork.maxY
                let bandHeight = page.atmosphereHeight * artworkScale
                let regions = [
                    (CGRect(x: source.minX, y: source.minY + split, width: source.width, height: source.height - split),
                     CGRect(x: artwork.minX * scale, y: extent.height - artworkBottom * scale,
                            width: artwork.width * scale, height: overlap * artworkScale * scale)),
                    (CGRect(x: source.minX, y: source.minY, width: source.width, height: split),
                     CGRect(x: artwork.minX * scale, y: extent.height - (artworkBottom + bandHeight) * scale,
                            width: artwork.width * scale, height: bandHeight * scale))
                ]
                for (crop, frame) in regions {
                    let sx = frame.width / crop.width, sy = frame.height / crop.height
                    let placed = image.cropped(to: crop).transformed(by: CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                        tx: frame.minX - crop.minX * sx, ty: frame.minY - crop.minY * sy))
                    result = placed.composited(over: result)
                }
            }
            return result
        }
        
        private func scaleToWidthAlignToTop(_ ciImage: CIImage, extent: CGRect) -> CIImage {
            let src = ciImage.extent
            guard src.width > 0, src.height > 0 else { return ciImage }
            let artwork = artworkFrame
            let displayScale = extent.width / max(1, bounds.width)
            let scaleX = artwork.width * displayScale / src.width
            let tx = extent.minX + artwork.minX * displayScale - src.minX * scaleX
            let ty = extent.maxY - artwork.minY * displayScale - src.maxY * scaleX
            return ciImage
                .transformed(by: CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleX, tx: tx, ty: ty))
                .cropped(to: extent)
        }

        private func prepareImageForRender(at extent: CGRect) -> PreparedRender {
            var result = PreparedRender()
            
            let shouldShowPreview = currentModel.shouldShowPreview
            switch currentModel.pageState {
            case let .staticPage(page):
                result.image = prepareSideImage(for: page, extent: extent, shouldShowPreview: shouldShowPreview)
                result.isStatic = true
                result.hasPreview = shouldShowPreview && page.image != nil
                
            case let .transition(leftPage, rightPage, progress):
                assert(progress > 0 && progress < 1)
                var effectiveTransition = currentModel.transitionType
                if !currentModel.isExpanded {
                    effectiveTransition = .dissolve
                }
                let leftSideImage = prepareSideImage(for: leftPage, extent: extent, shouldShowPreview: shouldShowPreview)
                let rightSideImage = prepareSideImage(for: rightPage, extent: extent, shouldShowPreview: shouldShowPreview)
                result.hasPreview = shouldShowPreview && (leftPage.image != nil || rightPage.image != nil)
                result.isStatic = false
                switch effectiveTransition {
                case .dissolve:
                    let filter = CIFilter.dissolveTransition()
                    filter.targetImage = rightSideImage
                    filter.inputImage = leftSideImage
                    filter.time = Float(progress)
                    result.image = filter.outputImage
                    
                case .swipe2:
                    let filter = CIFilter.swipeTransition()
                    filter.targetImage = rightSideImage
                    filter.inputImage = leftSideImage
                    filter.angle = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 0 : -.pi
                    filter.time = Float(progress)
                    filter.width = Float(extent.width * NftDetailsPageWipe.widthRatio)
                    filter.opacity = 0
                    filter.extent = extent
                    result.image = filter.outputImage
                }
            }
            
            // iOS 16 specifics: coordinate system is upside-down
            if #unavailable(iOS 17), let image = result.image {
                result.image = image.transformed(
                    by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -extent.height)
                )
            }
            
            return result
        }
                
        private func render() {
            guard let mtkView = metalView else { return }

            let extent = CGRect.fromSize(mtkView.drawableSize)
            guard extent.width > 0, extent.height > 0 else { return }

            preparedRender = prepareImageForRender(at: extent)
        }
        
        private func imageForCurrentFrame() -> CIImage? {
            guard let start = loadingFadeStart, let from = loadingFadeImage, let to = preparedRender.image else {
                return preparedRender.image
            }
            let progress = min(1, (CACurrentMediaTime() - start) / loadingFadeDuration)
            if progress >= 1 {
                loadingFadeStart = nil
                loadingFadeImage = nil
                updatePreferredFrameRate(isTransitioning: currentModel.pageState.isTransitioning)
                return to
            }
            let filter = CIFilter.dissolveTransition()
            filter.inputImage = from
            filter.targetImage = to
            filter.time = Float(progress * progress * (3 - 2 * progress))
            return filter.outputImage
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
        
        func draw(in view: MTKView) {
            let perfName: StaticString = if preparedRender.isStatic == true {
                preparedRender.hasPreview == true ? "bg_mtkDraw_static_with_preview" : "bg_mtkDraw_static"
            } else {
                preparedRender.hasPreview == true ? "bg_mtkDraw_transition_with_preview" : "bg_mtkDraw_transition"
            }
            let perf = NftDetailsPerformance.beginMeasure(perfName, tag: "\(view.preferredFramesPerSecond)hz")
            defer { NftDetailsPerformance.endMeasure(perf) }

            let perfDrawable = NftDetailsPerformance.beginMeasure("bg_mtkDraw_getDrawable")
            guard let drawable = view.currentDrawable else {
                NftDetailsPerformance.endMeasure(perfDrawable)
                return
            }
            NftDetailsPerformance.endMeasure(perfDrawable)
            
            let destBounds = CGRect.fromSize(width: CGFloat(drawable.texture.width), height: CGFloat(drawable.texture.height))
            guard destBounds.width > 0, destBounds.height > 0, let queue = commandQueue, let context = ciContext else { return }
            guard let commandBuffer = queue.makeCommandBuffer() else {
                assertionFailure()
                return
            }
            commandBuffer.label = "NftDetailsBgTransition"
            
            let imageToRender = imageForCurrentFrame() ?? solidColorImage(extent: destBounds, color: nil)
            context.render(imageToRender, to: drawable.texture, commandBuffer: commandBuffer, bounds: destBounds, colorSpace: colorSpace)
            
            commandBuffer.commit()
            commandBuffer.waitUntilScheduled()
            drawable.present()
        }
    }
    
    enum TransitionType {
        case swipe2
        case dissolve
    }
    
    struct PageModel: CustomStringConvertible, Equatable {
        let backgroundColor: UIColor?
        let image: CIImage?
        let tag: String
        var atmosphereImage: CIImage? = nil
        var atmosphereHeight: CGFloat = 200
        var hasLiveAtmosphere = false
        var description: String { "<'\(tag)' BG: \(backgroundColor == nil ? "-" : "✓") FG: \(image == nil ? "-" : "✓")>" }
    }

    typealias PageState = NftDetailsPageTransitionState<PageModel>

    struct Model: CustomStringConvertible, Equatable {
        let pageState: PageState
        let isExpanded: Bool
        let shouldShowPreview: Bool
        let heroFrame: CGRect
        var shouldShowAtmosphere = false
        var contentOffsetY: CGFloat = 0
        var isViewportMoving = false
        let transitionType = TransitionType.swipe2

        var hasLiveAtmosphere: Bool {
            guard isExpanded, shouldShowAtmosphere else { return false }
            switch pageState {
            case .staticPage(let page): return page.hasLiveAtmosphere
            case .transition(let left, let right, _): return left.hasLiveAtmosphere || right.hasLiveAtmosphere
            }
        }
        
        var description: String { "<\(pageState), expanded: \(isExpanded), showPreview: \(shouldShowPreview)>" }
        var preferLowResolutionRender: Bool { !isExpanded && !shouldShowPreview }
    }
}

extension NftDetailsPageTransitionState where Page == NftDetailsBackground.PageModel {
    func edgeColor(fallback: UIColor) -> UIColor {
        switch self {
        case .staticPage(let page):
            return page.backgroundColor ?? fallback
        case .transition(let left, let right, let progress):
            return (left.backgroundColor ?? fallback)
                .nftBlended(with: right.backgroundColor ?? fallback, fraction: progress)
        }
    }
}

extension UIColor {
    func nftBlended(with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return fraction < 0.5 ? self : other
        }
        let t = max(0, min(1, fraction))
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
