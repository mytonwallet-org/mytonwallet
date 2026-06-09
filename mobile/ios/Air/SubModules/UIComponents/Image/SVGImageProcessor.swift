import Foundation
import Kingfisher
@preconcurrency import SwiftSVG
import UIKit

public struct SVGImageProcessor: ImageProcessor {
    public static let `default` = SVGImageProcessor()

    public let identifier = "org.mytonwallet.air.svg-image-processor.v1"

    public init() {}

    public func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        switch item {
        case .image:
            return DefaultImageProcessor.default.process(item: item, options: options)
        case .data(let data):
            guard Self.isSVG(data) else {
                return DefaultImageProcessor.default.process(item: item, options: options)
            }
            return Self.renderSVG(data, scale: options.scaleFactor)
        }
    }

    private static func isSVG(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(512), encoding: .utf8) else {
            return false
        }

        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmedPrefix.hasPrefix("<svg") || trimmedPrefix.contains("<svg")
    }

    private static func renderSVG(_ data: Data, scale: CGFloat) -> UIImage? {
        let state = SVGRenderState()
        let semaphore = DispatchSemaphore(value: 0)

        _ = CALayer(SVGData: data) { svgLayer in
            state.finish(renderedImage(from: svgLayer, scale: scale))
            semaphore.signal()
        }

        waitForRender(state: state, semaphore: semaphore)
        return state.image
    }

    private static func waitForRender(state: SVGRenderState, semaphore: DispatchSemaphore) {
        if Thread.isMainThread {
            let deadline = Date(timeIntervalSinceNow: 3)
            while !state.isFinished && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        } else {
            _ = semaphore.wait(timeout: .now() + .seconds(3))
        }
    }

    private static func renderedImage(from svgLayer: SVGLayer, scale: CGFloat) -> UIImage? {
        let bounds = renderBounds(for: svgLayer)
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale > 0 ? scale : 1

        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            svgLayer.render(in: context.cgContext)
        }
    }

    private static func renderBounds(for svgLayer: SVGLayer) -> CGRect {
        for bounds in [svgLayer.bounds, CGRect(origin: .zero, size: svgLayer.frame.size), svgLayer.boundingBox] {
            let standardized = bounds.standardized
            if standardized.width > 0, standardized.height > 0, !standardized.isNull, !standardized.isInfinite {
                return standardized
            }
        }

        return .zero
    }
}

private final class SVGRenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var _image: UIImage?
    private var _isFinished = false

    var image: UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return _image
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isFinished
    }

    func finish(_ image: UIImage?) {
        lock.lock()
        defer { lock.unlock() }
        _image = image
        _isFinished = true
    }
}
