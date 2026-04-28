import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import MetalKit
import SwiftUI

struct NftDetailsBackground {
    final class View: UIView, MTKViewDelegate {
        private var currentModel = Model(
            pageState: .staticPage(PageModel(background: nil, image: nil, tag: "idle")),
            isExpanded: false,
            shouldShowPreview: false
        )
        private var metalView: MTKView?
        private var ciContext: CIContext?
        private var commandQueue: MTLCommandQueue?
        private let deviceScale = UIScreen.main.scale
        private let colorSpace = CGColorSpaceCreateDeviceRGB()
        private var lastPreparedImage: CIImage?
        private var lastLayoutSizeForPrepare: CGSize = .init(width: -1, height: -1)

        private var isTransitionFpsCapActive = false
        private var isLowResDrawableActive = false
        
        init() {
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
            mtkView.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
            mtkView.isPaused = true
            mtkView.enableSetNeedsDisplay = true
            mtkView.framebufferOnly = false
            mtkView.colorPixelFormat = .bgra8Unorm
            metalView = mtkView
            addSubview(mtkView)
            
            NSLayoutConstraint.activate([
                mtkView.topAnchor.constraint(equalTo: topAnchor),
                mtkView.leadingAnchor.constraint(equalTo: leadingAnchor),
                mtkView.trailingAnchor.constraint(equalTo: trailingAnchor),
                mtkView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            
            // Warm-up: pre-compile CI/Metal shaders so the first visible frame is not delayed.
            // Two passes are needed:
            //   1. Basic solid-color path (static pages, fallback).
            //   2. Dissolve-transition path: CIAffineClamp + scale + CIDissolveTransition — the graph used
            //      for background-pattern transitions. Without this, the first transition triggers a
            //      Metal shader compilation on the main thread (~10-50 ms) that stalls the drawable pool.
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
                    ciContext.render(makeSolidFallback(extent: bounds), to: texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
                    commandBuffer.commit()
                    commandBuffer.waitUntilCompleted()
                }

                // Pass 2 — dissolve between two clamp-scaled dummy images (mirrors prepareSideImage + dissolve path).
                if let commandBuffer = commandQueue?.makeCommandBuffer() {
                    let dummyPattern = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 1))
                    let scaled = dummyPattern.clampedToExtent().transformed(by: CGAffineTransform(scaleX: 1, y: 4)).cropped(to: bounds)
                    let dissolve = CIFilter.dissolveTransition()
                    dissolve.inputImage = scaled
                    dissolve.targetImage = scaled
                    dissolve.time = 0.5
                    if let output = dissolve.outputImage {
                        ciContext.render(output, to: texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
                    }
                    commandBuffer.commit()
                    commandBuffer.waitUntilCompleted()
                }
            }
        }

        private func updatePreferredFrameRate(isTransitioning: Bool) {
            if isTransitionFpsCapActive != isTransitioning {
                isTransitionFpsCapActive = isTransitioning
                metalView?.preferredFramesPerSecond = isTransitioning ? 60 : UIScreen.main.maximumFramesPerSecond
            }
        }

        private func updateDrawableResolution(isLowRes: Bool, force: Bool = false) {
            guard force || isLowResDrawableActive != isLowRes else { return }

            let size = bounds.size
            guard size.width > 0, size.height > 0 else { return }

            let k: CGFloat = isLowRes ? 0.5 : 1.0
            isLowResDrawableActive = isLowRes
            metalView?.drawableSize = CGSize(width: size.width * deviceScale * k, height: size.height * deviceScale * k)
        }
                
        func setModel(_ model: Model) {
            let perf = NftDetailsPerformance.beginMeasure("bg_setModel")
            defer { NftDetailsPerformance.endMeasure(perf) }

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
        
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                render()
            }
        }
        
        private func makeSolidFallback(extent: CGRect) -> CIImage {
            let uiColor = NftDetailsContentPalette.defaultBackgroundColor.resolvedColor(with: traitCollection)
            return CIImage(color: CIColor(cgColor: uiColor.cgColor)).cropped(to: extent)
        }
                
        private func translateImage(_ image: CIImage, x: CGFloat = 0, y: CGFloat = 0) -> CIImage {
            let transform = CGAffineTransform(translationX: x, y: y)
            return image.transformed(by: transform)
        }
        
        private func prepareSideImage(background: CIImage?, image: CIImage?, at extent: CGRect) -> CIImage {
            var result: CIImage
            if let background {
                result = scaleToExtent(background, extent: extent)
            } else {
                result = makeSolidFallback(extent: extent)
            }
            
            if let image {
                result = scaleToWidthAlignToTop(image, extent: extent).composited(over: result)
            }
            
            return result
        }
       
        private func prepareImageForRender(at extent: CGRect) -> CIImage? {
            let perfPrepare = NftDetailsPerformance.beginMeasure("bg_prepareForRender")
            defer { NftDetailsPerformance.endMeasure(perfPrepare) }

            
            let shouldShowPreview = currentModel.shouldShowPreview
            switch currentModel.pageState {
            case let .staticPage(page):
                return  prepareSideImage(background: page.background, image: shouldShowPreview ? page.image : nil, at: extent)
                
            case let .transition(leftPage, rightPage, progress):
                assert(progress > 0 && progress < 1)
                var effectiveTransition = currentModel.transitionType
                if !currentModel.isExpanded {
                    effectiveTransition = .dissolve
                }
                let leftSideImage = prepareSideImage(background: leftPage.background, image: shouldShowPreview ? leftPage.image: nil, at: extent)
                let rightSideImage = prepareSideImage(background: rightPage.background, image: shouldShowPreview ? rightPage.image : nil, at: extent)
                switch effectiveTransition {
                case .dissolve:
                    let filter = CIFilter.dissolveTransition()
                    filter.targetImage = rightSideImage
                    filter.inputImage = leftSideImage
                    filter.time = Float(progress)
                    return filter.outputImage

                case .swipe2:
                    let filter = CIFilter.swipeTransition()
                    filter.targetImage = rightSideImage
                    filter.inputImage = leftSideImage
                    filter.angle = -.pi
                    filter.time = Float(progress)
                    filter.width = Float(extent.width * 3)
                    filter.opacity = 0
                    filter.extent = extent
                    return filter.outputImage
                }
            }
        }
                
        private func render() {
            guard let mtkView = metalView else { return }
            
            let extent = CGRect(origin: .zero, size: mtkView.drawableSize)
            guard extent.width > 0, extent.height > 0 else { return }

            lastPreparedImage = prepareImageForRender(at: extent)
            mtkView.setNeedsDisplay()
        }
        
        private func scaleToWidthAlignToTop(_ ciImage: CIImage, extent: CGRect) -> CIImage {
            let normalized = translateImage(ciImage, x: -ciImage.extent.origin.x, y: -ciImage.extent.origin.y)
            let src = normalized.extent
            guard src.width > 0, src.height > 0 else { return ciImage }
            let scaleX = extent.width / src.width
            let scaled = normalized.cropped(to: src).transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleX))
            let sc = scaled.extent
            let moved = translateImage(scaled, x: extent.minX - sc.minX, y: (extent.minY + extent.height) - (sc.minY + sc.height))
            let transparent = CIImage.clear.cropped(to: extent)
            return moved.composited(over: transparent).cropped(to: extent)
        }

        private func scaleToExtent(_ ciImage: CIImage, extent: CGRect) -> CIImage {
            let normalized = translateImage(ciImage, x: -ciImage.extent.origin.x, y: -ciImage.extent.origin.y)
            let src = normalized.extent
            guard src.width > 0, src.height > 0 else { return ciImage }
            let scaleX = extent.width / src.width
            let scaleY = extent.height / src.height
            let clamped = normalized.clampedToExtent()
            let scaled = clamped.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            return scaled.cropped(to: extent)
        }
                
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
        
        func draw(in view: MTKView) {
            let perf = NftDetailsPerformance.beginMeasure("bg_mtkDraw")
            defer { NftDetailsPerformance.endMeasure(perf) }

            NftDetailsPerformance.markMtkBackgroundDraw()

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
            
            let perfRender = NftDetailsPerformance.beginMeasure("bg_mtkDraw_ciRender")
            let imageToRender = lastPreparedImage ?? makeSolidFallback(extent: destBounds)
            context.render(imageToRender, to: drawable.texture, commandBuffer: commandBuffer, bounds: destBounds, colorSpace: colorSpace)
            NftDetailsPerformance.endMeasure(perfRender)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    enum TransitionType {
        case swipe2
        case dissolve
    }
    
    struct PageModel: CustomStringConvertible, Equatable {
        let background: CIImage?
        let image: CIImage?
        let tag: String
        var description: String { "<'\(tag)' BG: \(background == nil ? "-" : "✓") FG: \(image == nil ? "-" : "✓")>" }
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
