import CoreGraphics
import Foundation

final class AnimationFrameBuffer {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let length: Int

    private let storage: UnsafeMutableRawPointer

    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
    private static let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    )

    init(width: Int, height: Int, bytesPerRow: Int) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.length = bytesPerRow * height
        self.storage = UnsafeMutableRawPointer.allocate(byteCount: self.length, alignment: 64)
        memset(self.storage, 0, self.length)
    }

    deinit {
        self.storage.deallocate()
    }

    var bytes: UnsafeMutablePointer<UInt8> {
        self.storage.assumingMemoryBound(to: UInt8.self)
    }

    func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) -> Result) -> Result {
        body(UnsafeRawBufferPointer(start: self.storage, count: self.length))
    }

    func makeImage() -> CGImage? {
        let retainedSelf = Unmanaged.passRetained(self)
        let releaseCallback: CGDataProviderReleaseDataCallback = { info, _, _ in
            guard let info else {
                return
            }
            Unmanaged<AnimationFrameBuffer>.fromOpaque(info).release()
        }

        guard let provider = CGDataProvider(
            dataInfo: retainedSelf.toOpaque(),
            data: self.storage,
            size: self.length,
            releaseData: releaseCallback
        ) else {
            retainedSelf.release()
            return nil
        }

        return CGImage(
            width: self.width,
            height: self.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: self.bytesPerRow,
            space: Self.colorSpace,
            bitmapInfo: Self.bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
