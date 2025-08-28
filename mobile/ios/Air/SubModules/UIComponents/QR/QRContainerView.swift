//
//  QRContainerView.swift
//  UIComponents
//
//  Created by Sina on 5/12/24.
//

import SwiftUI
import UIKit
import WalletContext

public protocol QRCodeContainerViewDelegate: AnyObject {
    func qrCodePressed()
}

public class QRCodeContainerView: UIView {

    private let url: String
    private let image: UIImage?
    private let imageURL: String?
    private weak var delegate: QRCodeContainerViewDelegate!
    public init(url: String,
                image: UIImage,
                size: CGFloat,
                centerImageSize: CGFloat = 50,
                delegate: QRCodeContainerViewDelegate) {
        self.url = url
        self.image = image
        self.imageURL = nil
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        setupView(size: size, centerImageSize: centerImageSize)
    }
    
    public init(url: String,
                imageURL: String,
                size: CGFloat,
                centerImageSize: CGFloat = 50,
                delegate: QRCodeContainerViewDelegate) {
        self.url = url
        self.image = nil
        self.imageURL = imageURL
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        setupView(size: size, centerImageSize: centerImageSize)
    }

    override public init(frame: CGRect) {
        fatalError()
    }
    
    required public init?(coder: NSCoder) {
        fatalError()
    }

    private func setupView(size: CGFloat, centerImageSize: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            //qrCodeContainer.widthAnchor.constraint(equalToConstant: 220),
            heightAnchor.constraint(equalToConstant: size)
        ])
        // qr code image
        let qrCode = WQrCode(url: url, width: size, height: size)
        qrCode.translatesAutoresizingMaskIntoConstraints = false
        addSubview(qrCode)
        NSLayoutConstraint.activate([
            qrCode.widthAnchor.constraint(equalToConstant: size),
            qrCode.heightAnchor.constraint(equalToConstant: size),
            qrCode.centerXAnchor.constraint(equalTo: centerXAnchor),
            qrCode.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        qrCode.layer.cornerRadius = 8
        qrCode.layer.masksToBounds = true
        // center image
        let centerImageView = UIImageView()
        if let image {
            centerImageView.image = image
        } else if let imageURL, let url = URL(string: imageURL) {
            centerImageView.kf.setImage(with: url)
        }
        centerImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerImageView)
        NSLayoutConstraint.activate([
            centerImageView.widthAnchor.constraint(equalToConstant: centerImageSize),
            centerImageView.heightAnchor.constraint(equalToConstant: centerImageSize),
            centerImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerImageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveLinear, animations: {
                self.alpha = 0.4
            }, completion: nil)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveLinear, animations: {
                self.alpha = 1.0
            }, completion: {_ in
                self.delegate.qrCodePressed()
            })
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveLinear, animations: {
                self.alpha = 1.0
            }, completion: nil)
        }
    }
}


public struct WUIQRCodeContainerView: UIViewRepresentable {
    
    let url: String
    let imageURL: String
    let size: CGFloat
    let onTap: () -> ()
    
    public init(url: String, imageURL: String, size: CGFloat, onTap: @escaping () -> Void) {
        self.url = url
        self.imageURL = imageURL
        self.size = size
        self.onTap = onTap
    }
    
    public final class Coordinator: QRCodeContainerViewDelegate {
        var onTap: () -> ()
        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }
        public func qrCodePressed() {
            onTap()
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }
    
    public func makeUIView(context: Context) -> QRCodeContainerView {
        let view = QRCodeContainerView(url: url, imageURL: imageURL, size: size, delegate: context.coordinator)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size),
            view.heightAnchor.constraint(equalToConstant: size)
        ])
        return view
    }
    
    public func updateUIView(_ uiView: QRCodeContainerView, context: Context) {
    }
}
