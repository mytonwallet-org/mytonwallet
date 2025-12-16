//
//  GlassActionButton.swift
//  MyTonWalletAir
//
//  Created by nikstar on 25.11.2025.
//

import UIKit
import WalletContext
import SwiftUI

@available(iOS 26, *)
class GlassActionButton: UIControl {
    
    // MARK: - Properties
    
    var title: String {
        didSet {
            titleLabel.text = title
        }
    }
    
    var image: UIImage? {
        didSet {
            imageView.image = image
        }
    }
    
    var action: () -> Void
    
    // MARK: - UI Components
    
    public let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: 13).isActive = true
        return label
    }()
    
    public let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .tintColor
        return view
    }()
    
    public let backgroundView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .center
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = .airBundle("ActionButtonBackground")
        view.clipsToBounds = true
        view.layer.cornerRadius = 24
        return view
    }()
    
    public lazy var glassEffectView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        effect.tintColor = WTheme.balanceHeaderView.background.withAlphaComponent(1)
        return UIVisualEffectView(effect: effect)
    }()
    
    // MARK: - Initialization
    
    init(title: String, image: UIImage?, action: @escaping () -> Void) {
        self.title = title
        self.image = image
        self.action = action
        
        super.init(frame: .zero)
        
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setup() {
        
        translatesAutoresizingMaskIntoConstraints = false
        
        glassEffectView.translatesAutoresizingMaskIntoConstraints = false
        glassEffectView.cornerConfiguration = .capsule()

        glassEffectView.contentView.addSubview(backgroundView)
        glassEffectView.contentView.addSubview(imageView)
        addSubview(titleLabel)
        addSubview(glassEffectView)
                
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 64),
            
            imageView.centerXAnchor.constraint(equalTo: glassEffectView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: glassEffectView.centerYAnchor),
            
            backgroundView.centerXAnchor.constraint(equalTo: glassEffectView.centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: glassEffectView.centerYAnchor),
            backgroundView.widthAnchor.constraint(equalTo: glassEffectView.widthAnchor),
            backgroundView.heightAnchor.constraint(equalTo: glassEffectView.heightAnchor),

            glassEffectView.topAnchor.constraint(equalTo: topAnchor, constant: -1),
            glassEffectView.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            glassEffectView.widthAnchor.constraint(equalTo: glassEffectView.heightAnchor),
            glassEffectView.heightAnchor.constraint(equalToConstant: 48).withPriority(.init(800)),

            titleLabel.topAnchor.constraint(equalTo: glassEffectView.bottomAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
        
        self.titleLabel.text = title
        self.imageView.image = image
        
        let g = UITapGestureRecognizer(target: self, action: #selector(didTap))
        glassEffectView.addGestureRecognizer(g)
    }
    
    @objc private func didTap() {
        action()
    }
}
