import Foundation
import Dispatch

enum AnimationRendererFrameType {
    case argb
    case yuva
}

protocol AnimationRenderer {
    // todo: switch to async api
    func render(queue: DispatchQueue, width: Int, height: Int, bytesPerRow: Int, data: Data, type: AnimationRendererFrameType, completion: @escaping @MainActor () -> Void)
}
