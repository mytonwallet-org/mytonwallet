import Foundation
import AVFoundation
import UIKit

private final class CameraPreviewNodeLayerNullAction: NSObject, CAAction {
    @objc func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable : Any]?) {
    }
}

private final class CameraPreviewNodeLayer: AVSampleBufferDisplayLayer {
    override func action(forKey event: String) -> CAAction? {
        return CameraPreviewNodeLayerNullAction()
    }
}

public final class CameraPreviewNode: UIView {
    private var displayLayer: AVSampleBufferDisplayLayer

    public init() {
        self.displayLayer = AVSampleBufferDisplayLayer()
        self.displayLayer.videoGravity = .resizeAspectFill

        super.init(frame: .zero)
        
        self.clipsToBounds = true        
        self.layer.addSublayer(self.displayLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func prepare() {
        DispatchQueue.main.async {
            self.displayLayer.flushAndRemoveImage()
        }
    }
    
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        self.displayLayer.enqueue(sampleBuffer)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()

        var transform = CGAffineTransform(rotationAngle: CGFloat.pi / 2.0)
        transform = transform.scaledBy(x: 1.0, y: 1.0)
        self.displayLayer.setAffineTransform(transform)
        self.displayLayer.frame = self.bounds
    }
}
