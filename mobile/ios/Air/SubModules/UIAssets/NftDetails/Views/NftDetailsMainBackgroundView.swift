import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import MetalKit
import SwiftUI

struct NftDetailsBackground {
    final class View: UIView, MTKViewDelegate {
        
        private var currentModel = Model(
            pageState: .staticPage(PageModel(backgroundColor: nil, image: nil, tag: "idle")),
            isExpanded: false,
            shouldShowPreview: false
        )
        
        private var metalView: MTKView?
        private var ciContext: CIContext?
        private var commandQueue: MTLCommandQueue?
        private let deviceScale = UIScreen.main.scale
        private let colorSpace = CGColorSpaceCreateDeviceRGB()
        private var lastLayoutSizeForPrepare: CGSize = .init(width: -1, height: -1)
        private var fallbackColor: UIColor
        private var isTransitionFpsCapActive = false
        private var isLowResDrawableActive = false

        private struct PreparedRender {
            var image: CIImage?
            var isStatic = true
            var hasPreview: Bool = false
        }
        private var preparedRender = PreparedRender()

        init() {
            fallbackColor = NftDetailsContentPalette.defaultBackgroundColor
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
            
            updateFallbackColor()
            
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
        private static var activeFramesPerSecond: Int { UIScreen.main.maximumFramesPerSecond }

        private func updatePreferredFrameRate(isTransitioning: Bool) {
            guard isTransitionFpsCapActive != isTransitioning else { return }
            isTransitionFpsCapActive = isTransitioning
            metalView?.preferredFramesPerSecond = isTransitioning ? Self.activeFramesPerSecond : Self.idleFramesPerSecond
        }

        private func updateDrawableResolution(isLowRes: Bool, force: Bool = false) {
            guard force || isLowResDrawableActive != isLowRes else { return }

            let size = bounds.size
            guard size.width > 0, size.height > 0 else { return }

            // For now it always has the best resolution. Tune when needed
            let k = isLowRes ? 0.2 : 1.0
            isLowResDrawableActive = isLowRes
            let newSize = CGSize(width: size.width * deviceScale * k, height: size.height * deviceScale * k)
            if metalView?.drawableSize != newSize {
                metalView?.drawableSize = newSize
            }
        }
                
        func setModel(_ model: Model) {
            guard currentModel != model else { return }
            currentModel = model
                        
            updatePreferredFrameRate(isTransitioning: model.pageState.isTransitioning)
            updateDrawableResolution(isLowRes: model.preferLowResolutionRender)
            
            render()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            
            let size = bounds.size
            if size != lastLayoutSizeForPrepare {
                lastLayoutSizeForPrepare = size
                updateDrawableResolution(isLowRes: currentModel.preferLowResolutionRender, force: true)
                render()
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            metalView?.isPaused = (window == nil)
        }
        
        private func updateFallbackColor() {
            fallbackColor = NftDetailsContentPalette.defaultBackgroundColor.resolvedColor(with: traitCollection)
        }
        
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                updateFallbackColor()
                render()
            }
        }
        
        private func solidColorImage(extent: CGRect, color: UIColor?) -> CIImage {
            let uiColor = color ?? fallbackColor
            return CIImage(color: CIColor(cgColor: uiColor.cgColor)).cropped(to: extent)
        }
                
        private func prepareSideImage(for page: PageModel, extent: CGRect, shouldShowPreview: Bool) -> CIImage {
            var result: CIImage
            result = solidColorImage(extent: extent, color: page.backgroundColor)
            if shouldShowPreview, let image = page.image {
                result = scaleToWidthAlignToTop(image, extent: extent).composited(over: result)
            }
            return result
        }
        
        private func scaleToWidthAlignToTop(_ ciImage: CIImage, extent: CGRect) -> CIImage {
            let src = ciImage.extent
            guard src.width > 0, src.height > 0 else { return ciImage }
            let scaleX = extent.width / src.width
            let tx = extent.minX - src.minX * scaleX
            let ty = (extent.minY + extent.height) - (src.minY + src.height) * scaleX
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
                    filter.angle = -.pi
                    filter.time = Float(progress)
                    filter.width = Float(extent.width * 3)
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
            
            let imageToRender = preparedRender.image ?? solidColorImage(extent: destBounds, color: nil)
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
        var description: String { "<'\(tag)' BG: \(backgroundColor == nil ? "-" : "✓") FG: \(image == nil ? "-" : "✓")>" }
    }

    typealias PageState = NftDetailsPageTransitionState<PageModel>

    struct Model: CustomStringConvertible, Equatable {
        let pageState: PageState
        let isExpanded: Bool
        let shouldShowPreview: Bool
        let transitionType = TransitionType.swipe2
        
        var description: String { "<\(pageState), expanded: \(isExpanded), showPreview: \(shouldShowPreview)>" }
        var preferLowResolutionRender: Bool { !shouldShowPreview }
    }
}
