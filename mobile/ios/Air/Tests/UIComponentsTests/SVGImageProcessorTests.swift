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

    @Test func preservesViewportPaddingAndRendersEverySizeAtTheSameResolution() async throws {
        let image = try await render("""
        <svg width="56" height="56" viewBox="0 0 56 56">
          <path d="M28 7L40 28L28 49L16 28Z" fill="#808080"/>
        </svg>
        """)
        #expect(image.size == CGSize(width: 256, height: 256))
        #expect(try pixel(image, x: 2, y: 28, side: 56)[3] == 0)
        #expect(try pixel(image, x: 28, y: 28, side: 56)[3] > 250)

        let large = try await render("""
        <svg viewBox="0 0 4096 4096"><circle cx="2048" cy="2048" r="2048" fill="orange"/></svg>
        """)
        #expect(large.size == CGSize(width: 256, height: 256))
    }

    @Test func mapsAnOffsetViewBoxIntoAViewportOfAnotherSize() async throws {
        let image = try await render("""
        <svg width="4096" height="4096" viewBox="-185 151 40 40">
          <rect x="-185" y="151" width="20" height="40" fill="red"/>
        </svg>
        """)
        #expect(image.size == CGSize(width: 256, height: 256))
        #expect(try pixel(image, x: 5, y: 20)[0] > 250)
        #expect(try pixel(image, x: 35, y: 20)[3] == 0)
    }

    @Test func appliesStyleSheetRulesBySpecificityAndGroupFillsOnlyWhereChildrenSetNone() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <style>.a, .b { stroke-width: 0; } .a { fill: red; } rect.b { fill: lime; }</style>
          <rect class="a" width="10" height="40"/>
          <rect class="b" x="10" width="10" height="40"/>
          <g fill="blue"><rect x="20" width="10" height="40" fill="white"/><g><rect x="30" width="10" height="40"/></g></g>
        </svg>
        """)
        let a = try pixel(image, x: 5, y: 20)
        let b = try pixel(image, x: 15, y: 20)
        let own = try pixel(image, x: 25, y: 20)
        let inherited = try pixel(image, x: 35, y: 20)
        #expect(a[0] > 250 && a[1] < 5)
        #expect(b[1] > 250 && b[0] < 5)
        #expect(own[0] > 250 && own[1] > 250 && own[2] > 250)
        #expect(inherited[2] > 250 && inherited[0] < 5)
    }

    @Test func combinesStopOpacityWithAColorDeclaredAfterIt() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <rect width="40" height="40" fill="url(#paint)"/>
          <linearGradient id="paint"><stop style="stop-opacity:0;stop-color:#fff"/><stop offset="1" style="stop-opacity:0;stop-color:#fff"/></linearGradient>
        </svg>
        """)
        #expect(try pixel(image, x: 20, y: 20)[3] == 0)
    }

    @Test func rendersUseClippedByAForwardReferencedClipPath() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40" xmlns:xlink="http://www.w3.org/1999/xlink">
          <use xlink:href="#square" clip-path="url(#left)"/>
          <defs>
            <rect id="square" width="40" height="40" fill="red"/>
            <clipPath id="left"><circle cx="0" cy="20" r="20"/></clipPath>
          </defs>
        </svg>
        """)
        #expect(try pixel(image, x: 5, y: 20)[0] > 250)
        #expect(try pixel(image, x: 30, y: 20)[3] == 0)
    }

    @Test func drawsEmbeddedPNGsButNeitherOtherFormatsNorRemoteImages() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <image width="12" height="40" preserveAspectRatio="none" href="data:image/png;base64,\(Self.bluePixels)"/>
          <image x="14" width="12" height="40" preserveAspectRatio="none" href="data:image/gif;base64,\(Self.redGIFPixel)"/>
          <image x="28" width="12" height="40" href="https://example.com/image.png"/>
        </svg>
        """)
        let embedded = try pixel(image, x: 6, y: 20)
        #expect(embedded[2] > 250 && embedded[0] < 5)
        #expect(try pixel(image, x: 20, y: 20)[3] == 0)
        #expect(try pixel(image, x: 34, y: 20)[3] == 0)
    }

    @Test func appliesPaintOpacityWhateverTheDeclarationOrder() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <style>.blue { fill: blue; }</style>
          <rect class="blue" width="20" height="40" fill="rgba(255, 0, 0, 0.5)"/>
          <g stroke="red"><path d="M30 0V40" style="stroke-opacity:0.5;stroke-width:8"/></g>
        </svg>
        """)
        let overridden = try pixel(image, x: 10, y: 20)
        #expect(overridden[2] > 250 && overridden[3] > 250)
        let stroke = try pixel(image, x: 30, y: 20)
        #expect(stroke[3] > 110 && stroke[3] < 145)
    }

    @Test func appliesClipPathTransformsAndStylesOfUse() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40" xmlns:xlink="http://www.w3.org/1999/xlink">
          <style>#copy { fill: lime; }</style>
          <defs>
            <rect id="square" width="40" height="40"/>
            <clipPath id="right" transform="translate(20 0)"><rect width="20" height="40"/></clipPath>
          </defs>
          <use id="copy" xlink:href="#square" clip-path="url(#right)"/>
        </svg>
        """)
        #expect(try pixel(image, x: 10, y: 20)[3] == 0)
        let right = try pixel(image, x: 30, y: 20)
        #expect(right[1] > 250 && right[0] < 5)
    }

    @Test func clipsKeepTheGradientExtentAndInheritedStrokes() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <style>/* Comments can
             span lines */ .clipped { clip-path: url(#left); }</style>
          <clipPath id="left"><rect width="20" height="40"/></clipPath>
          <linearGradient id="paint"><stop stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
          <rect class="clipped" width="40" height="20" fill="url(#paint)"/>
          <g stroke="red" stroke-width="4"><rect class="clipped" x="4" y="24" width="32" height="12" fill="none"/></g>
        </svg>
        """)
        let gradient = try pixel(image, x: 18, y: 10)
        #expect(gradient[3] > 250 && gradient[0] < 150)
        #expect(try pixel(image, x: 30, y: 10)[3] == 0)
        #expect(try pixel(image, x: 10, y: 24)[0] > 250)
        #expect(try pixel(image, x: 21, y: 30)[3] == 0)
    }

    @Test func keepsHardGradientStopsSharpInSmallViewBoxes() async throws {
        let image = try await render("""
        <svg viewBox="0 0 24 24">
          <rect width="24" height="24" fill="url(#paint)"/>
          <linearGradient id="paint"><stop offset=".5" stop-color="#f00"/><stop offset=".5" stop-color="#00f"/></linearGradient>
        </svg>
        """)
        // The output pixels on either side of the stop.
        let red = try pixel(image, x: 11.93, y: 12, side: 24)
        let blue = try pixel(image, x: 12.07, y: 12, side: 24)
        #expect(red[0] > 220 && red[2] < 35)
        #expect(blue[2] > 220 && blue[0] < 35)
    }

    @Test func parsesFunctionalColorsAndRejectsMalformedOnes() async throws {
        let image = try await render("""
        <svg viewBox="0 0 40 40">
          <rect width="20" height="40" fill="rgba(255, 0, 0, 0.5)"/>
          <rect x="20" width="20" height="40" fill="color(display-p3 0 0 1)" stroke="rgba(0,"/>
        </svg>
        """)
        let translucent = try pixel(image, x: 10, y: 20)
        #expect(translucent[3] > 110 && translucent[3] < 145)
        #expect(try pixel(image, x: 30, y: 20)[2] > 200)
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

    /// A 1 × 1 red GIF.
    private static let redGIFPixel = "R0lGODlhAQABAIAAAP8AAP///yH5BAAAAAAALAAAAAABAAEAAAICRAEAOw=="

    /// A 2 × 2 blue PNG.
    private static let bluePixels = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEElEQVR4nGNgYPj/H4KhDAA/0gf5tBJPzQAAAABJRU5ErkJggg=="

    /// Reads the pixel at a point in the coordinates of a square view box with the given side.
    private func pixel(_ image: UIImage, x: CGFloat, y: CGFloat, side: CGFloat = 40) throws -> [UInt8] {
        let bitmap = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(data: storage.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        }
        let column = min(bitmap.width - 1, Int(x / side * CGFloat(bitmap.width)))
        let row = min(bitmap.height - 1, Int(y / side * CGFloat(bitmap.height)))
        let offset = (row * bitmap.width + column) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
