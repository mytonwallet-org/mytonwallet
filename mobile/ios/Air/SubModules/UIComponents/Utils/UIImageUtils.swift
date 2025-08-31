//
//  UIImageUtils.swift
//  UIComponents
//
//  Created by Sina on 3/26/24.
//

import UIKit
import Kingfisher
import WalletCore
import WalletContext

public extension UIImage {
    func resized(to newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
    func with(backgroundColors: [CGColor], circleSize: CGSize) -> UIImage? {
        // Create a UIView to contain the icon and background
        let containerView = UIView(frame: CGRect(origin: .zero, size: circleSize))
        
        // Add circular gradient background
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(origin: .zero, size: circleSize)
        gradientLayer.colors = backgroundColors
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        
        let backgroundView = UIView(frame: CGRect(origin: .zero, size: circleSize))
        backgroundView.layer.addSublayer(gradientLayer)
        backgroundView.layer.cornerRadius = circleSize.width / 2
        backgroundView.clipsToBounds = true
        containerView.addSubview(backgroundView)
        
        // Add icon as UIImageView
        let iconImageView = UIImageView(image: self)
        iconImageView.contentMode = .center
        iconImageView.frame = CGRect(origin: .zero, size: circleSize)
        containerView.addSubview(iconImageView)
        
        // Render the UIView as UIImage
        let renderer = UIGraphicsImageRenderer(size: containerView.bounds.size)
        let image = renderer.image { context in
            containerView.layer.render(in: context.cgContext)
        }
        return image
    }
    
    static func downloadImage(url: URL, callback: @escaping ((UIImage?) -> Void)) {
        ImageDownloader.default.downloadImage(with: url,
                                              progressBlock: nil) { res in
            switch res {
            case .success(let imageRes):
                callback(imageRes.image)
                break
            case .failure(_):
                callback(nil)
                break
            }
        }
    }

    static func avatar(for account: MAccount?, withSize size: CGFloat) -> UIImage? {
        UIImage(named: "AddressIcon", in: AirBundle, compatibleWith: nil)?
            .with(backgroundColors: (account?.firstAddress ?? "").gradientColors,
                  circleSize: CGSize(width: size, height: size))?
            .withRenderingMode(.alwaysOriginal)
    }

}
