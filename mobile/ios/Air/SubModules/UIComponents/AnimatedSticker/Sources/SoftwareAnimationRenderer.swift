import Foundation
import UIKit
import Dispatch
import YUVConversion

final class SoftwareAnimationRenderer: UIImageView, AnimationRenderer {
    func render(queue: DispatchQueue, width: Int, height: Int, bytesPerRow: Int, data: Data, type: AnimationRendererFrameType, completion: @escaping () -> Void) {
        queue.async { [weak self] in
            let calculatedBytesPerRow = (4 * Int(width) + 15) & (~15)
            assert(bytesPerRow == calculatedBytesPerRow)
            
            let image = generateImagePixel(CGSize(width: CGFloat(width), height: CGFloat(height)), scale: 1.0, pixelGenerator: { _, pixelData, bytesPerRow in
                switch type {
                case .yuva:
                    data.withUnsafeBytes { rawBuffer in
                        guard let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                            return
                        }
                        decodeYUVAToRGBA(bytes, pixelData, Int32(width), Int32(height), Int32(bytesPerRow))
                    }
                case .argb:
                    data.withUnsafeBytes { rawBuffer in
                        guard let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                            return
                        }
                        memcpy(pixelData, bytes, data.count)
                    }
                }
            })
            
            DispatchQueue.main.async {
                self?.image = image
                completion()
            }
        }
    }
}
