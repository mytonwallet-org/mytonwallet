//
//  WActivityIndicator.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/29/24.
//

import UIKit
import WalletContext

public class WActivityIndicator: UIView {

    private var imageView: UIImageView!
    private var showAnimationWorkItem: DispatchWorkItem? = nil
    private var _isAnimating: Bool = false
    public var isAnimating: Bool {
        get {
            return _isAnimating
        }
        set {
            _isAnimating = newValue
        }
    }
    public var presentationDelay = CGFloat()

    public init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(named: "ActivityIndicator", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = WTheme.secondaryLabel
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leftAnchor.constraint(equalTo: leftAnchor),
            imageView.rightAnchor.constraint(equalTo: rightAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        alpha = 0
        isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var tintColor: UIColor! {
        set {
            imageView.tintColor = newValue
        }
        get {
            imageView.tintColor
        }
    }
    
    public func startAnimating(animated: Bool) {
        guard !isAnimating else { return }
        isAnimating = true
        isHidden = false

        @MainActor func action() {
            let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation")
            rotationAnimation.toValue = NSNumber(value: Double.pi * 2)
            rotationAnimation.duration = 0.625
            rotationAnimation.isCumulative = true
            rotationAnimation.repeatCount = Float.infinity
            rotationAnimation.isRemovedOnCompletion = false
            
            layer.add(rotationAnimation, forKey: "rotationAnimation")
            
            if animated {
                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                    self.alpha = 1
                }
            } else {
                self.alpha = 1
            }
        }
        
        showAnimationWorkItem?.cancel()
        showAnimationWorkItem = DispatchWorkItem(block: { [weak self] in
            action()
            self?.showAnimationWorkItem = nil
        })
        
        if presentationDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + presentationDelay, execute: showAnimationWorkItem!)
        } else {
            DispatchQueue.main.async {
                self.showAnimationWorkItem?.perform()
            }
        }
    }
    
    public func stopAnimating(animated: Bool) {
        guard isAnimating else { return }

        showAnimationWorkItem?.cancel()
        showAnimationWorkItem = nil
        isAnimating = false
        
        func action() {
            layer.removeAnimation(forKey: "rotationAnimation")
            isHidden = true
        }
        
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn], animations: {
                self.alpha = 0
            }, completion: { _ in
                if self.isAnimating {
                    return
                }
                action()
            })
        } else {
            self.alpha = 0
            action()
        }
    }
}
