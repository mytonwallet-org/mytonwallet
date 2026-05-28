//
//  StartVC.swift
//  UICreateWallet
//
//  Created by Sina on 3/31/23.
//

import UIKit
import SwiftUI
import WalletContext

private let emitterSize: CGFloat = 100

public final class ParticleBackgroundView: UIView {

    private var emitterLayer = CAEmitterLayer()

    public var baseColor: UIColor = .systemBlue {
        didSet {
            if baseColor != oldValue {
                setupLayers()
            }
        }
    }

    private lazy var circleImage: CGImage = Self.renderParticle(size: 20, cornerRadius: 10, color: .white)
    private lazy var roundedSquareImage: CGImage = Self.renderParticle(size: 24, cornerRadius: 6, color: .white)
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        emitterLayer.frame = bounds
        emitterLayer.emitterPosition = bounds.center
        emitterLayer.emitterSize = CGSize(width: emitterSize, height: emitterSize)
    }
    
    private func setup() {
        isUserInteractionEnabled = false
        layer.addSublayer(emitterLayer)
        setupLayers()
    }
    
    private func setupLayers() {
        setupEmitterLayer()
//        setupBurstEmitterLayer()
    }
    
    private func setupEmitterLayer() {
        _setupEmitterLayer(emitterLayer)
    }
    
    private func _setupEmitterLayer(_ emitterLayer: CAEmitterLayer) {
        emitterLayer.renderMode = .unordered
        emitterLayer.emitterShape = .circle
        emitterLayer.emitterMode = .outline
        emitterLayer.birthRate = 1.0
        rebuildCells(emitterLayer)
    }

    private func rebuildCells(_ emitterLayer: CAEmitterLayer) {
        let c1 = makeCell(image: circleImage,  scale: 0.20, scaleRange: 0.08, alpha: 0.45)
        let c2 = makeCell(image: circleImage,  scale: 0.10, scaleRange: 0.05, alpha: 0.30)
        let s1 = makeCell(image: roundedSquareImage, scale: 0.22, scaleRange: 0.10, alpha: 0.35)
        let s2 = makeCell(image: roundedSquareImage, scale: 0.12, scaleRange: 0.06, alpha: 0.28)
        emitterLayer.emitterCells = [c1, c2, s1, s2]
    }

    private func makeCell(image: CGImage, scale: CGFloat, scaleRange: CGFloat, alpha: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        cell.color = baseColor.withAlphaComponent(alpha).cgColor
        cell.birthRate = 2.0
        cell.lifetime = 50
        cell.lifetimeRange = 6.0
        cell.velocity = 14.0
        cell.velocityRange = 10.0
        cell.emissionRange = .pi * 2
        cell.scale = scale
        cell.scaleRange = scaleRange
        cell.scaleSpeed = -0.002
        cell.alphaSpeed = -1.0 / Float(cell.lifetime)
        cell.spin = 0.002
        cell.spinRange = 0.0008
        return cell
    }
    
    private static func renderParticle(size: CGFloat, cornerRadius: CGFloat, color: UIColor) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
            
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            color.setFill()
            path.fill()
        }
        return image.cgImage!
    }

    public func burst(duration: CFTimeInterval = 0.15) {
        let burstLayer = CAEmitterLayer()
        _setupEmitterLayer(burstLayer)
        layer.addSublayer(burstLayer)
        burstLayer.frame = layer.bounds
        burstLayer.emitterPosition = bounds.center
        burstLayer.emitterSize = CGSize(width: emitterSize, height: emitterSize)
        burstLayer.seed = UInt32.random(in: 0...UInt32.max)
        burstLayer.beginTime = CACurrentMediaTime()
        burstLayer.birthRate = 100
        burstLayer.velocity = 1.5
        burstLayer.lifetime = 1 / burstLayer.velocity
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            burstLayer.birthRate = 0
            try? await Task.sleep(for: .seconds(30))
            burstLayer.removeFromSuperlayer()
        }
    }
}


@MainActor
final class ParticleDemoViewController: UIViewController {

    private let particles = ParticleBackgroundView()
    private let iconView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Background particles
        particles.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(particles)
        NSLayoutConstraint.activate([
            particles.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            particles.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            particles.topAnchor.constraint(equalTo: view.topAnchor),
            particles.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Placeholder "icon"
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.backgroundColor = .systemBlue.withAlphaComponent(1.1)
        iconView.layer.cornerRadius = 28
        iconView.layer.masksToBounds = true
        iconView.alpha = 0.4

        // Optional: a subtle shadow so it reads as a button
        iconView.layer.shadowOpacity = 0.2
        iconView.layer.shadowRadius = 10
        iconView.layer.shadowOffset = CGSize(width: 0, height: 6)
        iconView.layer.shadowColor = UIColor.black.cgColor

        view.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 144),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
        ])

        iconView.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(iconTapped(_:)))
        iconView.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    @objc private func iconTapped(_ g: UITapGestureRecognizer) {
        particles.burst()
    }
}

public struct ParticleBackground: UIViewRepresentable {
    
    public var color: UIColor = .systemBlue
    public var burstDuration: CFTimeInterval = 0.15
    @Binding public var burstTrigger: Int

    public final class Coordinator {
        var lastTriggerValue: Int = 0
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public init(color: UIColor = .systemBlue, burstDuration: CFTimeInterval = 0.15, burstTrigger: Binding<Int> = .constant(0)) {
        self.color = color
        self.burstDuration = burstDuration
        self._burstTrigger = burstTrigger
    }

    public func makeUIView(context: Context) -> ParticleBackgroundView {
        let v = ParticleBackgroundView()
        v.baseColor = color
        return v
    }

    public func updateUIView(_ uiView: ParticleBackgroundView, context: Context) {
        uiView.baseColor = color
        if context.coordinator.lastTriggerValue != burstTrigger {
            context.coordinator.lastTriggerValue = burstTrigger
            uiView.burst(duration: burstDuration)
        }
    }
}


@available(iOS 18, *)
#Preview {
    ParticleDemoViewController()
}
