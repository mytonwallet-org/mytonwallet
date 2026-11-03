import Kingfisher
import Testing
import UIKit
@testable import UIComponents

@Suite @MainActor
struct SVGImageProcessorTests {
    @Test func canDecodeOriginalSVGOnTheMainThread() throws {
        let image = SVGImageProcessor.cacheSerializer.image(with: Data("""
        <svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="red"/></svg>
        """.utf8), options: .init([.scaleFactor(1)]))
        #expect(try pixel(#require(image), x: 20, y: 20)[0] > 250)
    }

    @Test func preservesViewportPaddingAndCapsLargeSourceImages() async throws {
        let image = try await render("""
        <svg width="56" height="56" viewBox="0 0 56 56">
          <path d="M28 7L40 28L28 49L16 28Z" fill="#808080"/>
        </svg>
        """)
        #expect(image.size == CGSize(width: 56, height: 56))
        #expect(try pixel(image, x: 2, y: 28)[3] == 0)
        #expect(try pixel(image, x: 28, y: 28)[3] > 250)

        let large = try await render("""
        <svg viewBox="0 0 4096 4096"><circle cx="2048" cy="2048" r="2048" fill="orange"/></svg>
        """)
        #expect(large.size == CGSize(width: 256, height: 256))
    }

    @Test func rendersForwardReferencedGradientInsideItsPath() async throws {
        let image = try await render("""
        <svg width="40" height="40" viewBox="0 0 40 40">
          <path d="M10 10H30V30H10Z" fill="url(#paint)"/>
          <defs><linearGradient id="paint" x1="10" y1="10" x2="30" y2="10" gradientUnits="userSpaceOnUse">
            <stop stop-color="#00FF00"/><stop offset="1" stop-color="#FF00FF"/>
          </linearGradient></defs>
        </svg>
        """)
        let left = try pixel(image, x: 12, y: 20)
        let right = try pixel(image, x: 28, y: 20)
        #expect(left[1] > 180 && left[0] < 80)
        #expect(right[0] > 180 && right[2] > 180 && right[1] < 80)
        #expect(try pixel(image, x: 5, y: 20)[3] == 0)
    }

    @Test func rendersNamedColorsAndClassFills() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <style>.background { fill: red; } .symbol { fill: white; }</style>
          <path class="background" d="M0 0H40V40H0Z"/>
          <path class="symbol" d="M10 10H30V30H10Z"/>
        </svg>
        """)
        let background = try pixel(image, x: 2, y: 20)
        let symbol = try pixel(image, x: 20, y: 20)
        #expect(background[0] > 250 && background[1] < 5, "Background pixel: \(background)")
        #expect(symbol[0] > 250 && symbol[1] > 250 && symbol[2] > 250)
    }

    @Test func rendersAbsoluteAndRelativeEllipticalArcs() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <path d="M10 20A10 10 0 0 1 30 20a10 10 0 0 1-20 0Z" fill="white"/>
        </svg>
        """)
        #expect(try pixel(image, x: 20, y: 12)[3] > 250)
        #expect(try pixel(image, x: 20, y: 28)[3] > 250)
        #expect(try pixel(image, x: 11, y: 11)[3] == 0)
    }

    @Test func rendersForwardReferencedTransformedRadialGradientOnRectangle() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <rect width="40" height="40" fill="url(#paint)"/>
          <defs><radialGradient id="paint" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse"
                                gradientTransform="rotate(45) scale(56.57)">
            <stop stop-color="white"/><stop offset="1" stop-color="black"/>
          </radialGradient></defs>
        </svg>
        """)
        let start = try pixel(image, x: 2, y: 2)
        let end = try pixel(image, x: 37, y: 37)
        #expect(start[0] > 220 && start[3] > 250)
        #expect(end[0] < 40 && end[3] > 250)
    }

    @Test func outlineDoesNotCoverInheritedFillAndInlineGradient() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40" fill="none">
          <rect width="40" height="40" fill="red"/>
          <path d="M10 10H30V30H10Z" style="fill:url(#paint)"/>
          <rect x="1" y="1" width="38" height="38" stroke="blue" stroke-width="1"/>
          <path d="M1 1H39V39H1Z" style="fill:none;opacity:0.8;stroke:blue"/>
          <defs><radialGradient id="paint" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse"
                                gradientTransform="translate(20 20) rotate(90) scale(20)">
            <stop stop-color="white"/><stop offset="1" stop-color="black"/>
          </radialGradient></defs>
        </svg>
        """)
        let background = try pixel(image, x: 5, y: 20)
        let center = try pixel(image, x: 20, y: 20)
        #expect(background[0] > 250 && background[1] < 5)
        #expect(center[0] > 230 && center[1] > 230 && center[2] > 230)
    }

    private func render(_ svg: String) async throws -> UIImage {
        let image = await Task.detached {
            SVGImageProcessor.default.process(item: .data(Data(svg.utf8)), options: .init([.scaleFactor(1)]))
        }.value
        return try #require(image)
    }

    @Test func originalSVGAndProcessedBitmapCanBothBeReadFromCache() async throws {
        let image = await Task.detached {
            SVGImageProcessor.cacheSerializer.image(with: Data("""
            <svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="red"/></svg>
            """.utf8), options: .init([.scaleFactor(1)]))
        }.value
        let original = try #require(image)
        let encoded = try #require(SVGImageProcessor.cacheSerializer.data(with: original, original: nil))
        let decoded = try #require(SVGImageProcessor.cacheSerializer.image(with: encoded, options: .init([.scaleFactor(1)])))
        #expect(original.size == decoded.size)
        #expect(try pixel(decoded, x: 20, y: 20)[0] > 250)
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> [UInt8] {
        let bitmap = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(data: storage.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        }
        let offset = (y * bitmap.width + x) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
