import Metal
import simd
import XCTest
@testable import UIComponents

@MainActor
final class AgentSpinningTopMaterialTests: XCTestCase {
    func testRestingTopKeepsItsTransparencyWithoutABackdrop() throws {
        let pixels = try render(pitch: 0.16, hasBackdrop: false, strength: 0)
        let translucentPixels = stride(from: 3, to: pixels.count, by: 4).filter {
            (10...245).contains(pixels[$0])
        }.count
        // This covers the body of the top, not just antialiasing along its silhouette.
        XCTAssertGreaterThan(translucentPixels, 5_000)
    }

    func testHeldTopStillRefractsTheBackdrop() throws {
        let plain = try render(pitch: 0.7)
        let grid = try render(pitch: 0.7, grid: true)
        var displacedSamples = 0
        for y in 0..<512 where (10..<45).contains(y % 50) {
            for x in 0..<512 where (10..<45).contains(x % 50) {
                let offset = (y * 512 + x) * 4
                guard plain[offset + 3] == 255 else { continue }
                // The source is white here, beyond the blur's reach from a grid line. Dark pixels must have moved
                // here through the lens, rather than merely showing the unchanged background through the coating.
                if (0..<3).contains(where: { Int(plain[offset + $0]) - Int(grid[offset + $0]) >= 20 }) {
                    displacedSamples += 1
                }
            }
        }
        XCTAssertGreaterThan(displacedSamples, 100)
    }

    /// The thin film shifts the coating's colours toward its own and keeps the top as translucent, on dark and light
    func testIridescenceShiftsTheColoursAndKeepsTheTopTranslucent() throws {
        for isDark in [false, true] {
            let plain = try render(pitch: 0.16, hasBackdrop: false, strength: 0, isDark: isDark)
            let iridescent = try render(pitch: 0.16, hasBackdrop: false, strength: 0, isDark: isDark, iridescence: 1)
            var changed = 0
            var translucent = 0
            for offset in stride(from: 0, to: plain.count, by: 4) where plain[offset + 3] > 10 {
                if (0..<3).contains(where: { abs(Int(plain[offset + $0]) - Int(iridescent[offset + $0])) >= 12 }) {
                    changed += 1
                }
                if (10...245).contains(iridescent[offset + 3]) { translucent += 1 }
            }
            XCTAssertGreaterThan(changed, 2_000, "Dark \(isDark): the film shows")
            XCTAssertGreaterThan(translucent, 5_000, "Dark \(isDark): still see-through")
        }
    }

    /// A large top stands on the ground: under its point a shadow darkens a light background and a faint glow lights a
    /// dark one, and its reflection shows below; without the ground nothing is drawn there
    func testGroundShowsUnderTheLargeTopOnly() throws {
        for isDark in [false, true] {
            let plain = try render(pitch: 0.16, hasBackdrop: false, strength: 0, isDark: isDark)
            let grounded = try render(pitch: 0.16, hasBackdrop: false, strength: 0, isDark: isDark, showsGround: true)
            // Below the point, which stands at y 150 from the bottom of the 512 px drawable
            var plainBelow = 0
            var groundedBelow = 0
            for y in (512 - 150 + 4)..<(512 - 150 + 60) {
                for x in 156..<356 {
                    let offset = (y * 512 + x) * 4
                    if (0..<4).contains(where: { plain[offset + $0] > 3 }) { plainBelow += 1 }
                    if (0..<4).contains(where: { grounded[offset + $0] > 3 }) { groundedBelow += 1 }
                }
            }
            XCTAssertEqual(plainBelow, 0, "Dark \(isDark): nothing below a top without the ground")
            XCTAssertGreaterThan(groundedBelow, 500, "Dark \(isDark): its shadow or glow and its reflection")
        }
        XCTAssertFalse(AgentSpinningTopView().showsGround, "Tops stand on no ground by default")
        XCTAssertTrue(AgentSpinningTopView(showsGround: true).showsGround)
    }

    private func render(
        pitch: Float,
        grid: Bool = false,
        hasBackdrop: Bool = true,
        strength: Float = 1,
        isDark: Bool = false,
        iridescence: Float = 0,
        showsGround: Bool = false
    ) throws -> [UInt8] {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(SpinningTopRenderer(device: device))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let side = 512
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let color = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let backdrop = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var background = (0..<(side * side)).map { index -> UInt32 in
            let isLine = index % side % 50 < 5 || index / side % 50 < 5
            return grid && isLine ? 0xff999999 : 0xffffffff
        }
        backdrop.replace(
            region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
            withBytes: &background, bytesPerRow: side * 4
        )
        let targets = DiamondRenderTargetCache()
        let pass = try XCTUnwrap(targets.renderPass(resolving: color, sampleCount: renderer.sampleCount))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        let tiltAndSpin = SpinningTopRenderer.tiltAndSpin(yaw: 0, lean: 0.09, leanDirection: 0)
        let camera = SpinningTopRenderer.camera(pitch: pitch)
        let ground = showsGround ? SpinningTopRenderer.makeGround(
            tiltAndSpin: tiltAndSpin, camera: camera, placement: SIMD4(256, 150, 200, 512), drawableWidth: 512, isDark: isDark
        ) : nil
        renderer.encode(encoder: encoder, uniforms: .init(
            rotation: camera * tiltAndSpin,
            placement: SIMD4(256, 150, 200, 512),
            parameters: SIMD4(512, strength, isDark ? 1 : 0, hasBackdrop ? 1 : 0),
            backdrop: SIMD4(0, 0, 512, 512),
            material: SIMD4(0.25, 0, -SpinningTopGeometry.restingOffset.x, -SpinningTopGeometry.restingOffset.y),
            effects: SIMD4(iridescence, 0, 0, 0)
        ), backdrop: hasBackdrop ? backdrop : nil, ground: ground)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        color.getBytes(&pixels, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        return pixels
    }
}
