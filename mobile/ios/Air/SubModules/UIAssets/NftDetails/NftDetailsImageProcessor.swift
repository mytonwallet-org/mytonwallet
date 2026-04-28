import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import WalletContext

private let log = Log("NftDetails.ImageProcessor")

class NftDetailsImageProcessor {
    private let deviceScale: CGFloat
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    lazy var ciContext: CIContext = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            assertionFailure()
            return CIContext(options: [
                .useSoftwareRenderer: false,
                .cacheIntermediates: true,
                .workingColorSpace: colorSpace,
                .outputColorSpace: colorSpace
            ])
        }
        return CIContext(mtlDevice: device, options: [
            .cacheIntermediates: true,
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace
        ])
    }()
    
    @MainActor
    init() {
        self.deviceScale = UIScreen.main.scale
    }
        
    private struct Gradient1 {
        let image: CIImage
        let size: CGSize
    }

    private let gradientCacheLock = NSLock()
    private var cachedGradient1: Gradient1?
    
    private func getGradient1(forSize size: CGSize, locationK: CGFloat) -> CIImage? {
        gradientCacheLock.lock()
        defer { gradientCacheLock.unlock() }
        
        if let cached = cachedGradient1, cached.size.equalTo(size) {
            return cached.image
        }
        cachedGradient1 = nil
                
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let start = CGPoint(x: size.width / 2, y: 0)
            let end = CGPoint(x: size.width / 2, y: size.height)
                 
            let c = UIColor.red
            let colors = [
                c.withAlphaComponent(0).cgColor,
                c.withAlphaComponent(0.3).cgColor,
                c.withAlphaComponent(0.6).cgColor,
                c.withAlphaComponent(0.85).cgColor,
                c.withAlphaComponent(0.98).cgColor,
                c.withAlphaComponent(1.0).cgColor
            ] as CFArray
            
            
            let s = locationK
            let locations: [CGFloat] = [
                0.0,
                0.1 * s,
                0.2 * s,
                0.3 * s,
                0.4 * s,
                0.5 * s
            ]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                ctx.cgContext.drawLinearGradient(gradient, start: start, end: end, options: [.drawsAfterEndLocation])
            }
        }
                
        if let cgImage = image.cgImage {
            let ciImage = CIImage(cgImage: cgImage)
            cachedGradient1 = Gradient1(image: ciImage, size: size)
            return ciImage
        }
        
        return nil
    }
                
    private func blurBottomArea(_ image: CIImage, blurRadius: CGFloat, bottomHeight: CGFloat, gradientK: CGFloat) throws (IntError) -> CIImage {
        // Get bottom band of the composite
        var extent = image.extent
        extent.size.height = bottomHeight
        let cropped = image.cropped(to: extent)
        
        // Blur it. Preparation is necessary for clear edges
        let clampFilter = CIFilter.affineClamp()
        clampFilter.inputImage = cropped
        clampFilter.transform = CGAffineTransform.identity
        guard let clamped = clampFilter.outputImage  else { throw IntError("BlurBottomArea.1") }
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = clamped
        blurFilter.radius = Float(blurRadius)
        guard let blurredOutput = blurFilter.outputImage?.cropped(to: extent)  else { throw IntError("BlurBottomArea.2") }
        
        // Apply a tint over
        let tintImage = solidColorImage(color: .black.withAlphaComponent(0.05), extent: extent)
        let tintedBlur = compositeImage(tintImage, background: blurredOutput)
                
        // Blend with gradient mask
        guard let gradientMask = getGradient1(forSize: extent.size, locationK: gradientK) else { throw IntError("BlurBottomArea.3")}
        let blended = try blendWithAlphaMask(topImage: tintedBlur, bottomImage: cropped, mask: gradientMask)
        
        // Add gradiented overlay
        let overlayGradientFilter = CIFilter.linearGradient()
        overlayGradientFilter.point0 = CGPoint(x: extent.width / 2, y: extent.height)
        overlayGradientFilter.color0 = CIColor(color: UIColor.black.withAlphaComponent(0))
        overlayGradientFilter.point1 = CGPoint(x: extent.width / 2, y: extent.height * (1.0 - gradientK))
        overlayGradientFilter.color1 = CIColor(color: UIColor.black.withAlphaComponent(0.32))
        guard let overlayGradient = overlayGradientFilter.outputImage?.cropped(to: extent) else { throw IntError("BlurBottomArea.4")}
        let overlayFilter = CIFilter.overlayBlendMode()
        overlayFilter.inputImage = overlayGradient
        overlayFilter.backgroundImage = blended
        guard let overlaid = overlayFilter.outputImage else { throw IntError("BlurBottomArea.5")}

        // Compose with original image
        return compositeImage(overlaid, background: image)
    }

    private func blendWithAlphaMask(topImage: CIImage, bottomImage: CIImage, mask: CIImage) throws (IntError) -> CIImage {
        let maskFilter = CIFilter.blendWithAlphaMask()
        maskFilter.inputImage = topImage
        maskFilter.maskImage = mask
        guard let maskedTop = maskFilter.outputImage else { throw IntError("Unable to blend with alpha mask.") }

        return compositeImage(maskedTop, background: bottomImage)
    }
           
    private func solidColorImage(color: UIColor, extent: CGRect) -> CIImage { CIImage(color: CIColor(color: color)).cropped(to: extent) }

    private func compositeImage(_ topImage: CIImage, background: CIImage) -> CIImage { topImage.composited(over: background) }

    private struct IntError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
    
    private func cropToSquare(_ image: CIImage) -> CIImage {
        let imgSize = image.extent.size
        let imgWidth = imgSize.width
        let imgHeight = imgSize.height
        let cropRect: CGRect
        if imgHeight > imgWidth {
            cropRect = CGRect(x: 0, y: round((imgHeight - imgWidth) / 2), width: imgWidth, height: imgWidth)
        } else
        if imgHeight < imgWidth {
            cropRect = CGRect(x: round((imgWidth - imgHeight) / 2), y: 0, width: imgHeight, height: imgHeight)
        } else {
            return image
        }
        return translateImage(image.cropped(to: cropRect), x: -cropRect.origin.x, y: -cropRect.origin.y)
    }
    
    private func fitToWidth(_ image: CIImage, maxWidth: CGFloat) throws(IntError) -> CIImage {
        let scale = maxWidth / image.extent.width
        guard scale < 1 else { return image }
           
        let scaleFilter = CIFilter.lanczosScaleTransform()
        scaleFilter.inputImage = image.clampedToExtent()
        scaleFilter.scale = Float(scale)
        scaleFilter.aspectRatio = 1.0
        guard let scaled = scaleFilter.outputImage else { throw IntError("Failed to apply Lanczos scale transform") }
            
        return scaled.cropped(to: .fromSize(width: floor(image.extent.width * scale), height: floor(image.extent.width * scale)))
    }
    
    private func mirrorBottom(_ image: CIImage, sourceBandHeight: CGFloat, targetScale: CGFloat) -> CIImage {
        let width = image.extent.width
        let targetHeight = sourceBandHeight * targetScale

        // get a bottom chunk from the original image
        let cropped = image.cropped(to: .init(x: 0,y: 0, width: width, height: sourceBandHeight))

        // Make borders infinite (remove edge artifacts), slip and scale
        let scaledUpsideDown = cropped.clampedToExtent().transformed(by: CGAffineTransform(scaleX: 1, y: -targetScale))
            
        // Crop to make extent finite
        let cropped2 = scaledUpsideDown.cropped(to: .init(x: 0, y: -targetHeight, width: width, height: targetHeight))
        
        // translate to proper position ready for further compsing
        let result = translateImage(cropped2, y: targetHeight)
        
        return result
    }
    
    private func regionColor(_ image: CIImage) -> UIColor? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        var bitmap = [UInt8](repeating: 0, count: 4)
        let bounds = CGRect.square(1)
        ciContext.render(filter.outputImage!, toBitmap: &bitmap, rowBytes: 4, bounds: bounds,  format: .RGBA8, colorSpace: colorSpace)
        
        // Experimental value: 120+ opaque level usually looks more or less good. More statistics will be collected in the future
        if bitmap[3] < 120 {
            return nil
        }
        
        func c(_ i: Int) -> CGFloat { CGFloat(bitmap[i]) / 255 }
        return UIColor(red: c(0), green: c(1), blue: c(2), alpha: c(3))
    }
    
    private func addBottomBand(_ image: CIImage, bottomBand: CGFloat, color: UIColor) -> CIImage {
        guard bottomBand > 0 else { return image }
        let extent = CGRect.fromSize(width: image.extent.width, height: bottomBand)
        let solid = solidColorImage(color: color, extent: extent)
        return compositeImage(translateImage(image, y: bottomBand), background: solid)
    }

    private func translateImage(_ image: CIImage, x: CGFloat = 0, y: CGFloat = 0) -> CIImage {
        let transform = CGAffineTransform(translationX: x, y: y)
        return image.transformed(by: transform)
    }
    
    private func backgroundPattern(cgImage: CGImage) throws (IntError) -> CIImage {
        let bottomRowHeight = 1.0
        let bottomRowRect = CGRect(x: 0, y: CGFloat(cgImage.height) - bottomRowHeight, width: CGFloat(cgImage.width), height: bottomRowHeight)
        guard let bottomRowCGImage = cgImage.cropping(to: bottomRowRect) else { throw IntError("CreateBackgroundPattern.Crop") }
        let bottomCI = ciImage(from: bottomRowCGImage)
        return translateImage(bottomCI, x: -bottomCI.extent.origin.x, y: -bottomCI.extent.origin.y)
    }
            
    func loadImage(_ image: UIImage, targetWidth: CGFloat, simplifiedProcessing: Bool) -> NftDetailsImage.Processed {
        let layoutBottomBand = 60.0
        let layoutMirroredBandHeight = 45.0
        let layoutTopBandHeight: CGFloat = 86.0
        let mirrorK = 3.0
        let targetHeight = layoutBottomBand + layoutMirroredBandHeight * mirrorK + layoutTopBandHeight
        
        let perfName: StaticString = simplifiedProcessing ? "image_process_simple" : "image_process"
        let perf = NftDetailsPerformance.beginMeasure(perfName)
        defer { NftDetailsPerformance.endMeasure(perf) }

        var result = NftDetailsImage.Processed()
        do {
            // Load image, crop to square, scale down if necessary
            guard var sourceImage = ciImageOptional(from: image) else { throw IntError("Failed to create CIImage from the source") }
            sourceImage = cropToSquare(sourceImage)
            sourceImage = try fitToWidth(sourceImage, maxWidth: targetWidth * deviceScale)
            result.originalImage = try uiImage(from: sourceImage)
            result.previewImage = result.originalImage
                                            
            let scaleK1 = sourceImage.extent.width / targetWidth
            func calcScale(_ v: CGFloat) -> CGFloat { (scaleK1 * v).rounded() }
            
            // For simplified processing we should stop here: square from original image + base color is all we need
            if simplifiedProcessing {
                let baseColor = regionColor(sourceImage.cropped(to: sourceImage.extent.copyWith(height: 1)))
                result.baseColor = baseColor
                if let baseColor {
                    let extent = sourceImage.extent.copyWith(height: 1)
                    let ciPattern = solidColorImage(color: baseColor, extent: extent)
                    result.setBackground(ciPattern, try uiImage(from: ciPattern))
                }
                result.previewCIImage = ciImageOptional(from: result.previewImage)
                return result
            }
            
            // Compose the final image frame: full + mirrored middle band + bottom band of solid color
            let bottomBand = calcScale(layoutBottomBand)
            var mirror = mirrorBottom(sourceImage, sourceBandHeight: calcScale(layoutMirroredBandHeight), targetScale: mirrorK)
            
            // Get a base color or exit
            var e = sourceImage.extent
            e.size.height = min(calcScale(layoutMirroredBandHeight * 2), e.size.height)
            let croppedForColor = sourceImage.cropped(to: e)
            guard let baseColor = regionColor(croppedForColor) else {
                result.previewCIImage = ciImageOptional(from: result.previewImage)
                return result
            }
            result.baseColor = baseColor

            // Overlay the mirrored area with a gradient
            do {
                let extent = mirror.extent
                let gradientFilter = CIFilter.linearGradient()
                gradientFilter.point0 = CGPoint(x: extent.width / 2, y: 0)
                gradientFilter.color0 = CIColor(color:  baseColor)
                gradientFilter.point1 = CGPoint(x: extent.width / 2, y: extent.height)
                gradientFilter.color1 = CIColor(color: baseColor.withAlphaComponent(0))
                let gradientExtent = CGRect.fromSize(extent.size)
                guard let gradient = gradientFilter.outputImage?.cropped(to: gradientExtent) else {
                    throw IntError("Failed to create gradient")
                }
                mirror = compositeImage(gradient, background: mirror)
            }
            
            // compose main image + mirrored one + solid color bottom band
            var composited =  compositeImage(mirror, background: translateImage(sourceImage, y: mirror.extent.height))
            composited = addBottomBand(composited, bottomBand: bottomBand, color: baseColor)
            
            // Apply tinted blurred overlay to the bottom
            let blurRadius =  40.0 * composited.extent.width / (402.0 * deviceScale)
            let h = mirror.extent.height + bottomBand + calcScale(layoutTopBandHeight)
            let gradientK = 195.0 / targetHeight
            let tintedBlurred = try blurBottomArea(composited, blurRadius: blurRadius, bottomHeight: h, gradientK: gradientK)

            // Create final images: large blurred one + stretchable bottom band
            let cgImage = try cgImage(from: tintedBlurred)
            result.previewImage = uiImage(from: cgImage)
            result.previewCIImage = ciImage(from: cgImage)
            let ciPattern = try backgroundPattern(cgImage: cgImage)
            result.setBackground(ciPattern, try uiImage(from: ciPattern))
            
        } catch {
            log.error("Unable load image: \(error)")
        }
        return result
    }
}

extension NftDetailsImageProcessor {
    private func cgImage(from ciImage: CIImage) throws (IntError) -> CGImage {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw IntError("Failed to create CGImage from CIImage")
        }
        return cgImage
    }

    private func uiImage(from cgImage: CGImage) -> UIImage {
        UIImage(cgImage: cgImage, scale: deviceScale, orientation: .up)
    }

    private func uiImage(from ciImage: CIImage) throws (IntError) -> UIImage {
        uiImage(from: try cgImage(from: ciImage))
    }
    
    func ciImage(from cgImage: CGImage) -> CIImage {
        CIImage(cgImage: cgImage, options: [.colorSpace: colorSpace])
    }

    func ciImageOptional(from cgImage: CGImage?) -> CIImage? {
        guard let cgImage else { return nil }
        return ciImage(from: cgImage)
    }

    func ciImageOptional(from uiImage: UIImage?) -> CIImage? {
        guard let uiImage else { return nil }
        return CIImage(image: uiImage, options: [.applyOrientationProperty: true])
    }
}
