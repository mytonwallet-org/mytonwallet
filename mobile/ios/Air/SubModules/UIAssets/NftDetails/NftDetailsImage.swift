import Kingfisher
import UIKit
import UIComponents

struct NftDetailsImage {

    static func noImagePlaceholderImage() -> UIImage {
        UIImage.airBundle("NoNftImage2")
    }

    struct Processed {
        var originalImage: UIImage?
        var previewImage: UIImage?
        var previewCIImage: CIImage?
        var baseColor: UIColor?
        var atmosphereColor: UIColor?
        var isPlaceholder = false

        private let atmosphereCache = AtmosphereCache()

        private final class AtmosphereCache {
            var size: CGSize = .zero
            var rendered: Atmosphere?
        }

        struct Atmosphere {
            let image: UIImage
            let ciImage: CIImage
        }

        /// Render at the final page height. Resizing a fixed-height reflection
        /// would change its required 4× vertical stretch on different titles.
        @MainActor
        func atmosphere(height: CGFloat, pageWidth: CGFloat) -> Atmosphere? {
            let size = CGSize(width: pageWidth, height: height)
            if atmosphereCache.size == size, let cached = atmosphereCache.rendered { return cached }
            guard height > 0, pageWidth > 0, let originalImage,
                  var source = CIImage(image: originalImage) else { return nil }
            let scale = source.extent.width / pageWidth
            source = source.composited(over: CIImage(color: CIColor(color: atmosphereColor ?? baseColor ?? .clear)).cropped(to: source.extent))
            let band = source.cropped(to: CGRect(x: source.extent.minX, y: source.extent.minY,
                width: source.extent.width, height: min(source.extent.height, NftDetailsImageProcessor.atmosphereSourceBandHeight * scale)))
            let rendered = NftDetailsImageProcessor.atmosphere(from: band, height: height * scale, scale: scale,
                color: atmosphereColor ?? baseColor ?? .clear, displayScale: screenScale, shade: !isPlaceholder)
            guard let cg = NftDetailsImageProcessor.atmosphereContext.createCGImage(rendered, from: rendered.extent) else { return nil }
            let result = Atmosphere(image: UIImage(cgImage: cg, scale: scale, orientation: .up), ciImage: CIImage(cgImage: cg))
            atmosphereCache.size = size
            atmosphereCache.rendered = result
            return result
        }

        var artworkPreviewImage: UIImage? {
            if let originalImage { return originalImage }
            guard let previewImage, let cg = previewImage.cgImage,
                  let square = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: cg.width)) else { return originalImage }
            return UIImage(cgImage: square, scale: previewImage.scale, orientation: .up)
        }

        private var atmosphereOverlapPixels: CGFloat {
            guard let image = previewCIImage else { return 0 }
            return (image.extent.height - image.extent.width) * NftDetailsImageProcessor.atmosphereOverlap
                / NftDetailsImageProcessor.atmosphereReferenceHeight
        }

        var atmosphereImage: UIImage? {
            guard let previewImage, let cg = previewImage.cgImage, cg.height > cg.width,
                  let strip = cg.cropping(to: CGRect(x: 0, y: CGFloat(cg.width) - atmosphereOverlapPixels, width: CGFloat(cg.width), height: CGFloat(cg.height - cg.width) + atmosphereOverlapPixels)) else { return nil }
            return UIImage(cgImage: strip, scale: previewImage.scale, orientation: .up)
        }

        var atmosphereCIImage: CIImage? {
            guard let image = previewCIImage, image.extent.height > image.extent.width else { return nil }
            return image.cropped(to: CGRect(x: image.extent.minX, y: image.extent.minY,
                width: image.extent.width, height: image.extent.height - image.extent.width + atmosphereOverlapPixels))
        }

        var artworkCIImage: CIImage? {
            if let originalImage, let source = CIImage(image: originalImage) {
                return source.composited(over: CIImage(color: CIColor(color: atmosphereColor ?? baseColor ?? .clear)).cropped(to: source.extent))
            }
            guard let image = previewCIImage else { return nil }
            let square = CGRect(x: image.extent.minX, y: image.extent.maxY - image.extent.width,
                                width: image.extent.width, height: image.extent.width)
            return image.cropped(to: square)
        }
    }
    
    enum ProcessedState: CustomStringConvertible {
        case idle
        case loading
        case loaded(NftDetailsImage.Processed)
        case failed(Error)
        
        var description: String {
            switch self {
            case .idle: "<idle>"
            case .loading: "<loading>"
            case .failed: "<loadFailed>"
            case .loaded: "<loaded>"
            }
        }
        
        var isIdle: Bool {
            if case .idle = self { return true }
            return false
        }
        
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }
    }
}

extension KingfisherError {
    var isNotFound: Bool {
        if case .responseError(let reason) = self,
           case .invalidHTTPStatusCode(let response) = reason {
            return response.statusCode == 404
        }
        return false
    }
}
