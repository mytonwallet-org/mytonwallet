import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import UIComponents
import WalletContext

private let log = Log("NftDetails.ImageProcessor")

class NftDetailsImageProcessor: @unchecked Sendable {
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
        self.deviceScale = screenScale
    }
        
    static let atmosphereContext = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpaceCreateDeviceRGB()
    ])

    private static let atmosphereTintOpacity: CGFloat = 0.05
    private static let atmosphereOverlayOpacity: CGFloat = 0.32

    static let atmosphereReferenceHeight: CGFloat = 200
    // Move only the start down from the original 86 pt overlap. Keep the
    // original completion point (11.5 pt below the edge) to conceal the hinge.
    static let atmosphereOverlap: CGFloat = 54
    static let atmosphereBlurRamp: CGFloat = atmosphereOverlap + 11.5
    static let atmosphereSourceBandHeight: CGFloat = 80

    static func reflectedBand(from source: CIImage, height: CGFloat) -> CIImage {
        source.clampedToExtent().transformed(by: CGAffineTransform(a: 1, b: 0, c: 0,
            d: -4, tx: 0, ty: height))
            .cropped(to: CGRect(x: 0, y: 0, width: source.extent.width, height: height))
    }

    /// Production pipeline: color gradient over the reflection, then a tinted
    /// blur through the original progressive alpha mask, then the dark overlay.
    static func atmosphere(from lowerBand: CIImage, height: CGFloat, scale: CGFloat,
                           color: UIColor, displayScale: CGFloat, shade: Bool = true) -> CIImage {
        let source = lowerBand.transformed(by: CGAffineTransform(translationX: -lowerBand.extent.minX, y: -lowerBand.extent.minY))
        let extent = CGRect(x: 0, y: 0, width: source.extent.width,
                            height: height + atmosphereOverlap * scale)
        let bottomBand = min(height, 60 * scale)
        let mirrorHeight = height - bottomBand
        var mirror = reflectedBand(from: source, height: mirrorHeight)
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: extent.midX, y: 0)
        gradient.color0 = CIColor(color: color)
        gradient.point1 = CGPoint(x: extent.midX, y: max(1, mirrorHeight))
        gradient.color1 = CIColor(color: color.withAlphaComponent(0))
        mirror = gradient.outputImage!.cropped(to: mirror.extent).composited(over: mirror)
        let solid = solidColorImage(color: color, extent: CGRect(x: 0, y: 0, width: extent.width, height: bottomBand))
        let composed = source.transformed(by: CGAffineTransform(translationX: 0, y: height))
            .composited(over: mirror.transformed(by: CGAffineTransform(translationX: 0, y: bottomBand)))
            .composited(over: solid)
        let radius = 40 * extent.width / (402 * displayScale)
        // Keep the production shade's 195 pt span. Only the blur mask starts
        // lower; its original six alpha stops still reach 100% at the same edge.
        let gradientK = 195 * scale / extent.height
        let maskGradientK = 2 * atmosphereBlurRamp * scale / extent.height
        return ((try? blurBottomArea(composed, blurRadius: radius,
                                     bottomHeight: extent.height, gradientK: gradientK, maskGradientK: maskGradientK, shade: shade)) ?? composed)
            .cropped(to: extent)
    }

    private struct Gradient1 {
        let image: CIImage
        let size: CGSize
        let locationK: CGFloat
    }

    private static let gradientCacheLock = NSLock()
    nonisolated(unsafe) private static var cachedGradient1: Gradient1?
    
    static func getGradient1(forSize size: CGSize, locationK: CGFloat) -> CIImage? {
        gradientCacheLock.lock()
        defer { gradientCacheLock.unlock() }
        
        if let cached = cachedGradient1, cached.size.equalTo(size), cached.locationK == locationK {
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

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                ctx.cgContext.drawLinearGradient(gradient, start: start, end: end, options: [.drawsAfterEndLocation])
            }
        }
                
        if let cgImage = image.cgImage {
            let ciImage = CIImage(cgImage: cgImage)
            cachedGradient1 = Gradient1(image: ciImage, size: size, locationK: locationK)
            return ciImage
        }
        
        return nil
    }
                
    private static func blurBottomArea(_ image: CIImage, blurRadius: CGFloat, bottomHeight: CGFloat, gradientK: CGFloat, maskGradientK: CGFloat, shade: Bool) throws (IntError) -> CIImage {
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
        let tintImage = solidColorImage(color: .black.withAlphaComponent(shade ? atmosphereTintOpacity : 0), extent: extent)
        let tintedBlur = compositeImage(tintImage, background: blurredOutput)
                
        // Blend with gradient mask
        guard let gradientMask = getGradient1(forSize: CGSize(width: 1, height: extent.height), locationK: maskGradientK) else { throw IntError("BlurBottomArea.3")}
        let blended = try blendWithAlphaMask(topImage: tintedBlur, bottomImage: cropped, mask: gradientMask.clampedToExtent())
        
        // Add gradiented overlay
        let overlayGradientFilter = CIFilter.linearGradient()
        overlayGradientFilter.point0 = CGPoint(x: extent.width / 2, y: extent.height)
        overlayGradientFilter.color0 = CIColor(color: UIColor.black.withAlphaComponent(0))
        overlayGradientFilter.point1 = CGPoint(x: extent.width / 2, y: extent.height * (1.0 - gradientK))
        overlayGradientFilter.color1 = CIColor(color: UIColor.black.withAlphaComponent(shade ? atmosphereOverlayOpacity : 0))
        guard let overlayGradient = overlayGradientFilter.outputImage?.cropped(to: extent) else { throw IntError("BlurBottomArea.4")}
        let overlayFilter = CIFilter.overlayBlendMode()
        overlayFilter.inputImage = overlayGradient
        overlayFilter.backgroundImage = blended
        guard let overlaid = overlayFilter.outputImage else { throw IntError("BlurBottomArea.5")}

        // Compose with original image
        return compositeImage(overlaid, background: image)
    }

    private static func blendWithAlphaMask(topImage: CIImage, bottomImage: CIImage, mask: CIImage) throws (IntError) -> CIImage {
        let maskFilter = CIFilter.blendWithAlphaMask()
        maskFilter.inputImage = topImage
        maskFilter.maskImage = mask
        guard let maskedTop = maskFilter.outputImage else { throw IntError("Unable to blend with alpha mask.") }

        return compositeImage(maskedTop, background: bottomImage)
    }
           
    private static func solidColorImage(color: UIColor, extent: CGRect) -> CIImage { CIImage(color: CIColor(color: color)).cropped(to: extent) }

    private static func compositeImage(_ topImage: CIImage, background: CIImage) -> CIImage { topImage.composited(over: background) }

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
    
    /// Sample the actual bottom background, ignoring small foreground accents.
    /// Transparent pixels never vote for the color of the page.
    static func bottomBackgroundColor(_ image: UIImage) -> UIColor? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let band = CGRect(x: (image.size.width - side) / 2,
                          y: (image.size.height - side) / 2 + side * 0.94,
                          width: side, height: side * 0.06)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let sample = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 8), format: format).image { _ in
            image.draw(in: CGRect(x: -band.minX * 64 / band.width, y: -band.minY * 8 / band.height,
                                  width: image.size.width * 64 / band.width,
                                  height: image.size.height * 8 / band.height))
        }
        guard let cgImage = sample.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: 64 * 8 * 4)
        guard let context = CGContext(data: &pixels, width: 64, height: 8, bitsPerComponent: 8,
                                      bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 8))
        var bins: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        var opaqueCount = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[i + 3] >= 200 else { continue }
            opaqueCount += 1
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let key = (r / 24) * 121 + (g / 24) * 11 + b / 24
            let old = bins[key] ?? (0, 0, 0, 0)
            bins[key] = (old.count + 1, old.r + Double(r), old.g + Double(g), old.b + Double(b))
        }
        guard opaqueCount > 64 * 8 / 3,
              let mode = bins.max(by: { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count < $1.value.count })?.value else { return nil }
        let divisor = Double(mode.count) * 255
        return UIColor(red: mode.r / divisor, green: mode.g / divisor, blue: mode.b / divisor, alpha: 1)
    }

    /// The atmosphere ends in a 5% black tint and a 32% black overlay.
    /// Resolve that same solid color without rendering the full blurred strip.
    static func pageBackgroundColor(_ color: UIColor) -> UIColor {
        let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
        let source = solidColorImage(color: color, extent: extent)
        let tinted = solidColorImage(color: .black.withAlphaComponent(atmosphereTintOpacity), extent: extent).composited(over: source)
        let overlay = CIFilter.overlayBlendMode()
        overlay.inputImage = solidColorImage(color: .black.withAlphaComponent(atmosphereOverlayOpacity), extent: extent)
        overlay.backgroundImage = tinted
        guard let output = overlay.outputImage else { return color }
        var pixel = [UInt8](repeating: 0, count: 4)
        atmosphereContext.render(output, toBitmap: &pixel, rowBytes: 4, bounds: extent,
                                 format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: 1)
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
    
    private func translateImage(_ image: CIImage, x: CGFloat = 0, y: CGFloat = 0) -> CIImage {
        let transform = CGAffineTransform(translationX: x, y: y)
        return image.transformed(by: transform)
    }
                
    func loadPlaceholder(_ image: UIImage, targetWidth: CGFloat, backgroundColor: UIColor) -> NftDetailsImage.Processed {
        let format = UIGraphicsImageRendererFormat()
        format.scale = deviceScale
        format.opaque = true
        let rect = CGRect(x: 0, y: 0, width: targetWidth, height: targetWidth)
        let flattened = UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            backgroundColor.setFill()
            ctx.fill(rect)
            image.draw(in: rect)
        }
        var result = loadImage(flattened, targetWidth: targetWidth, backgroundColor: backgroundColor)
        if let original = result.originalImage, let source = ciImageOptional(from: original) {
            let scale = source.extent.width / targetWidth
            let height = (Self.atmosphereReferenceHeight * scale).rounded()
            let band = source.cropped(to: source.extent.copyWith(height: min(source.extent.height, Self.atmosphereSourceBandHeight * scale)))
            let atmosphere = Self.atmosphere(from: band, height: height, scale: scale, color: backgroundColor, displayScale: deviceScale, shade: false)
            let combined = atmosphere.composited(over: translateImage(source, y: height))
            if let cg = try? cgImage(from: combined) {
                result.previewImage = uiImage(from: cg)
                result.previewCIImage = ciImage(from: cg)
            }
        }
        result.baseColor = backgroundColor
        result.atmosphereColor = backgroundColor
        result.isPlaceholder = true
        return result
    }

    func loadImage(_ image: UIImage, targetWidth: CGFloat, backgroundColor: UIColor? = nil) -> NftDetailsImage.Processed {
        let layoutBottomBand = Self.atmosphereReferenceHeight
        
        let perf = NftDetailsPerformance.beginMeasure("image_process")
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
            
            // Animated gifts use the same atmosphere as still NFTs. Transparent
            // artwork is composited over its resolved color for the preview only;
            // the original remains untouched for the media viewer.
            let baseColor = (Self.bottomBackgroundColor(image)
                ?? backgroundColor ?? regionColor(sourceImage) ?? UIColor(white: 0.16, alpha: 1)).withAlphaComponent(1)
            result.baseColor = baseColor
            result.atmosphereColor = baseColor
            sourceImage = sourceImage.composited(over: Self.solidColorImage(color: baseColor, extent: sourceImage.extent))
            let bottomBand = calcScale(layoutBottomBand)
            let band = sourceImage.cropped(to: sourceImage.extent.copyWith(height: min(sourceImage.extent.height, calcScale(Self.atmosphereSourceBandHeight))))
            let atmosphere = Self.atmosphere(from: band, height: bottomBand, scale: scaleK1, color: baseColor, displayScale: deviceScale)
            let softened = atmosphere.composited(over: translateImage(sourceImage, y: bottomBand))

            // Cache the sharp square and atmosphere together; render them in separate views.
            let cgImage = try cgImage(from: softened)
            let ciImage = ciImage(from: cgImage)
            result.previewImage = uiImage(from: cgImage)
            result.previewCIImage = ciImage
            result.baseColor = regionColor(ciImage.cropped(to: ciImage.extent.copyWith(height: 1)))
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
