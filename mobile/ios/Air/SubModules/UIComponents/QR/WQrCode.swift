//
//  WQrCode.swift
//  UIComponents
//
//  Created by Sina on 4/22/23.
//

import UIKit
import GZip
import RLottieBinding

// This view is a wrapper around `TransformImageView` which in fact is `TransformImageNode` from the original app
public class WQrCode: UIView {

    private var transformImageView: TransformImageView? = nil

    public init(url: String, width: CGFloat, height: CGFloat) {
        super.init(frame: .zero)
        setup(url: url, width: width, height: height)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // setup animation data
    private func setup(url: String, width: CGFloat, height: CGFloat) {
        transformImageView = TransformImageView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        addSubview(transformImageView!)

        // set loading signal
        if let (_, generator) = generateQrCode(string: url, color: .black, backgroundColor: .white, icon: .cutout) {
            transformImageView?.setContent(generator, attemptSynchronously: false)
        }
        
        // get makeImageLayout function from qrcode view
        let makeImageLayout = self.transformImageView!.asyncLayout()
        // make image layout with required properties
        let imageSize = CGSize(width: width, height: height)
        let imageApply = makeImageLayout(TransformImageArguments(corners: ImageCorners(),
                                                                 imageSize: imageSize,
                                                                 boundingSize: imageSize,
                                                                 intrinsicInsets: UIEdgeInsets(),
                                                                 emptyColor: nil))
        // apply!
        let _ = imageApply()
    }

}
