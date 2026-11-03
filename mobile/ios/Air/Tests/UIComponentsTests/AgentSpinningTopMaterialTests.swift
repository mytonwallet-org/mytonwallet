import Metal
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

    private func render(pitch: Float, grid: Bool = false, hasBackdrop: Bool = true, strength: Float = 1) throws -> [UInt8] {
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
        renderer.encode(encoder: encoder, uniforms: .init(
            rotation: SpinningTopRenderer.transform(yaw: 0, pitch: pitch, lean: 0.09, leanDirection: 0),
            placement: SIMD4(256, 150, 200, 512),
            parameters: SIMD4(512, strength, 0, hasBackdrop ? 1 : 0),
            backdrop: SIMD4(0, 0, 512, 512),
            material: SIMD4(0.25, 0, -SpinningTopGeometry.restingOffset.x, -SpinningTopGeometry.restingOffset.y)
        ), backdrop: hasBackdrop ? backdrop : nil)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        color.getBytes(&pixels, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        return pixels
    }
}
