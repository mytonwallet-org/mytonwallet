import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import MetalKit
import SwiftUI

struct NftDetailsBackground { }

extension NftDetailsBackground {
    
    enum Transition {
        case swipe
        case swipe2
        case dissolve
        
        var shouldBakeInImageIntoBackground: Bool { self != .swipe }
    }

    final class View: UIView, MTKViewDelegate {
        let transition = Transition.swipe2
        
        private var currentModel = Model.empty
        private var metalView: MTKView?
        private var ciContext: CIContext?
        private var commandQueue: MTLCommandQueue?
        private let deviceScale = UIScreen.main.scale
        private let colorSpace = CGColorSpaceCreateDeviceRGB()
        private var lastPreparedImage: CIImage?
        private var lastLayoutSizeForPrepare: CGSize = .init(width: -1, height: -1)
        
        var isExpanded = false

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
                .cacheIntermediates: false,
                .workingColorSpace: colorSpace,
                .outputColorSpace: colorSpace
            ])
            
            let mtkView = MTKView(frame: bounds, device: device)
            mtkView.translatesAutoresizingMaskIntoConstraints = false
            mtkView.delegate = self
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
            
            // A little warm-up. One-time CI/Metal shader compile so the first visible frame is not delayed.
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 4,
                height: 4,
                mipmapped: false
            )
            desc.usage = [.renderTarget, .shaderRead, .shaderWrite]
            if let texture = device.makeTexture(descriptor: desc), let commandBuffer = commandQueue?.makeCommandBuffer(), let ciContext {
                let bounds = CGRect.square(4)
                let image = makeSolidFallback(extent: bounds)
                ciContext.render(image, to: texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
            }
        }
                
        func setModel(_ model: Model) {
            if currentModel != model {
                currentModel = model
                render()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let size = bounds.size
            guard size != lastLayoutSizeForPrepare else { return }
            lastLayoutSizeForPrepare = size
            render()
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
       
        private func prepareBackgroundForRender(at extent: CGRect) -> CIImage? {
            let leftPage = currentModel.leftPage
            
            // Static: no transition, no image here, just draw backround pattern
            guard let rightPage = currentModel.rightPage else {
                assert(currentModel.sideProgress == 0)
                return  prepareSideImage(background: leftPage.background, image: nil, at: extent)
            }
            
            // Transition
            let progress = currentModel.sideProgress
            assert(progress > 0 && progress < 1)
            var effectiveTransition = transition
            if !isExpanded {
                effectiveTransition = .dissolve
            }
            let bakeInImage = transition.shouldBakeInImageIntoBackground && isExpanded
            let leftSideImage = prepareSideImage(background: leftPage.background, image: bakeInImage ? leftPage.image: nil, at: extent)
            let rightSideImage = prepareSideImage(background: rightPage.background, image: bakeInImage ? rightPage.image : nil, at: extent)
            switch effectiveTransition {
            case .swipe:
                let outputImage = leftSideImage.composited(over: translateImage(rightSideImage, x: extent.width))
                let b = extent.copyWith(x: extent.width * progress)
                let cropped = outputImage.cropped(to: b)
                return translateImage(cropped, x: -b.origin.x)

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
        
        private func render() {
            let extent = CGRect.fromSize(width: bounds.width * deviceScale, height: bounds.height * deviceScale)
            guard extent.width > 0, extent.height > 0 else { return }
            
            lastPreparedImage = prepareBackgroundForRender(at: extent)
            metalView?.setNeedsDisplay()
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
            guard let drawable = view.currentDrawable else { return }
            let destBounds = CGRect.fromSize(width: CGFloat(drawable.texture.width), height: CGFloat(drawable.texture.height))
            guard destBounds.width > 0, destBounds.height > 0, let queue = commandQueue, let context = ciContext else { return }
            guard let commandBuffer = queue.makeCommandBuffer() else { return }
                        
            let imageToRender = lastPreparedImage ?? makeSolidFallback(extent: destBounds)
            context.render(imageToRender, to: drawable.texture, commandBuffer: commandBuffer, bounds: destBounds, colorSpace: colorSpace)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

extension NftDetailsBackground {
    
    struct PageModel: CustomStringConvertible, Equatable {
        let background: CIImage?
        let image: CIImage?
        let tag: String
        var description: String { "<'\(tag)' BG: \(background == nil ? "-" : "✓") FG: \(image == nil ? "-" : "✓")>" }
    }
    
    struct Model: CustomStringConvertible, Equatable {
        let leftPage: PageModel
        let rightPage: PageModel?
        let sideProgress: CGFloat // if not 0 then the right must present (!= nil)
        
        var description: String {
            guard let rightPage else { return "STATIC \(leftPage)" }
            return "TRANSITION: \(leftPage) => \(rightPage) at \(sideProgress)"
        }
                
        static let empty = Model(
            leftPage: PageModel(background: nil, image: nil, tag: "idle"),
            rightPage: nil,
            sideProgress: 0,
        )
        
        init(leftPage: PageModel, rightPage: PageModel?, sideProgress: CGFloat) {
            
            // normalize the data. We either have a static left side at progress 0 or
            // have a transition left => right at 0..1 (both ends exclusive)
            var effectiveProgress = sideProgress
            var effectiveRight = rightPage
            var effectiveLeft = leftPage
            
            if effectiveProgress < 0 {
                effectiveProgress = 0
            }
            if effectiveProgress == 0 {
                effectiveRight = nil
            }
            if effectiveProgress > 0 {
                if let rightPage {
                    if effectiveProgress >= 1 {
                        effectiveLeft = rightPage
                        effectiveProgress = 0
                    }
                } else {
                    effectiveProgress = 0
                }
            }
            
            assert(effectiveProgress >= 0 && effectiveProgress < 1)
            assert(effectiveRight == nil || effectiveProgress > 0 )
            
            self.leftPage = effectiveLeft
            self.rightPage = effectiveRight
            self.sideProgress = effectiveProgress
        }
    }
}
