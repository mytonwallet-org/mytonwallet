import CoreImage
import Testing
import UIKit
@testable import UIComponents

@MainActor
struct QrCodeTests {
    @Test(arguments: [
        "ton://transfer/UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ",
        "T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb",
        "0x52908400098527886E0F7030069857D2E4169EE7",
        "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
    ], [CGFloat(2), CGFloat(3)])
    func `rendered receive QR preserves its payload`(payload: String, scale: CGFloat) throws {
        let (_, render) = try #require(generateQrCode(
            string: payload,
            color: .black,
            backgroundColor: .white,
            icon: .cutout
        ))
        let size = CGSize(width: 200, height: 200)
        let context = try #require(render(TransformImageArguments(
            corners: ImageCorners(),
            imageSize: size,
            boundingSize: size,
            intrinsicInsets: .zero,
            scale: scale
        )))
        let image = try #require(context.generateImage()?.cgImage)
        let detector = try #require(CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        let results = detector.features(in: CIImage(cgImage: image))
        #expect(results.count == 1)
        let result = try #require(results.first as? CIQRCodeFeature)
        #expect(result.messageString == payload)
    }
}
