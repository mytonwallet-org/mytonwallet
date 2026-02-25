//
//  QRScanView.swift
//  UIQRScan
//
//  Created by Sina on 5/14/23.
//

import UIKit
import UIComponents
import WalletContext
import QuartzCore

class QRScanView: UIView, UIScrollViewDelegate {

    private var previewView: CameraPreviewNode!

    private var focusView: UIView!
    // focus view constraints that hold it center of the screen, filled if no focused rect found
    private var focusViewConstraints: [NSLayoutConstraint]!

    // focus view constraints after qr code found
    private var focusViewLeftConstraint: NSLayoutConstraint? = nil
    private var focusViewTopConstraint: NSLayoutConstraint? = nil
    private var focusViewWidthConstraint: NSLayoutConstraint? = nil
    private var focusViewHeightConstraint: NSLayoutConstraint? = nil

    private var leftDimView: UIView!
    private var topDimView: UIView!
    private var rightDimView: UIView!
    private var bottomDimView: UIView!

    private var torchButton: GlassButton!

    //private var titleView: UILabel!
    
    private var camera: Camera!
    private var codesTask: Task<Void, Never>?
    private var lastCodeDeliveryDate: Date?
    
    var onCodeDetected: ((CameraCode?) -> Void)?
    
    init() {
        super.init(frame: .zero)
        setupViews()
        setupCamera()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        codesTask?.cancel()
        camera.stopCapture(invalidate: true)
    }
    
    func updateInForeground(_ inForeground: Bool) {
        if !inForeground {
            self.camera.stopCapture(invalidate: false)
        } else {
            self.camera.startCapture()
        }
    }
    
    private func defaultFocusAreaConstraints() -> [NSLayoutConstraint] {
        return [
            focusView.widthAnchor.constraint(equalToConstant: 260),
            focusView.heightAnchor.constraint(equalToConstant: 260),
            focusView.centerXAnchor.constraint(equalTo: centerXAnchor),
            focusView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
    }
    
    private func setupViews() {
        previewView = CameraPreviewNode()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.backgroundColor = .black
        addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.leftAnchor.constraint(equalTo: leftAnchor),
            previewView.rightAnchor.constraint(equalTo: rightAnchor),
            previewView.topAnchor.constraint(equalTo: topAnchor),
            previewView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        focusView = UIView()
        focusView.translatesAutoresizingMaskIntoConstraints = false
        focusView.backgroundColor = .clear
        addSubview(focusView)
        focusViewConstraints = defaultFocusAreaConstraints()
        NSLayoutConstraint.activate(focusViewConstraints)
        
        topDimView = UIView()
        topDimView.translatesAutoresizingMaskIntoConstraints = false
        topDimView.alpha = 0.625
        topDimView.backgroundColor = .black.withAlphaComponent(0.8)
        addSubview(topDimView)
        NSLayoutConstraint.activate([
            topDimView.leftAnchor.constraint(equalTo: leftAnchor),
            topDimView.rightAnchor.constraint(equalTo: rightAnchor),
            topDimView.topAnchor.constraint(equalTo: topAnchor),
            topDimView.bottomAnchor.constraint(equalTo: focusView.topAnchor)
        ])
        
        bottomDimView = UIView()
        bottomDimView.translatesAutoresizingMaskIntoConstraints = false
        bottomDimView.alpha = 0.625
        bottomDimView.backgroundColor = .black.withAlphaComponent(0.8)
        addSubview(bottomDimView)
        NSLayoutConstraint.activate([
            bottomDimView.leftAnchor.constraint(equalTo: leftAnchor),
            bottomDimView.rightAnchor.constraint(equalTo: rightAnchor),
            bottomDimView.topAnchor.constraint(equalTo: focusView.bottomAnchor),
            bottomDimView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        leftDimView = UIView()
        leftDimView.translatesAutoresizingMaskIntoConstraints = false
        leftDimView.alpha = 0.625
        leftDimView.backgroundColor = .black.withAlphaComponent(0.8)
        addSubview(leftDimView)
        NSLayoutConstraint.activate([
            leftDimView.leftAnchor.constraint(equalTo: leftAnchor),
            leftDimView.rightAnchor.constraint(equalTo: focusView.leftAnchor),
            leftDimView.topAnchor.constraint(equalTo: focusView.topAnchor),
            leftDimView.bottomAnchor.constraint(equalTo: focusView.bottomAnchor)
        ])
        
        rightDimView = UIView()
        rightDimView.translatesAutoresizingMaskIntoConstraints = false
        rightDimView.alpha = 0.625
        rightDimView.backgroundColor = .black.withAlphaComponent(0.8)
        addSubview(rightDimView)
        NSLayoutConstraint.activate([
            rightDimView.leftAnchor.constraint(equalTo: focusView.rightAnchor),
            rightDimView.rightAnchor.constraint(equalTo: rightAnchor),
            rightDimView.topAnchor.constraint(equalTo: focusView.topAnchor),
            rightDimView.bottomAnchor.constraint(equalTo: focusView.bottomAnchor)
        ])

        let frameView = UIImageView()
        frameView.translatesAutoresizingMaskIntoConstraints = false
        frameView.image = generateFrameImage()
        addSubview(frameView)
        NSLayoutConstraint.activate([
            frameView.leftAnchor.constraint(equalTo: focusView.leftAnchor, constant: -2),
            frameView.rightAnchor.constraint(equalTo: focusView.rightAnchor, constant: 2),
            frameView.topAnchor.constraint(equalTo: focusView.topAnchor, constant: -2),
            frameView.bottomAnchor.constraint(equalTo: focusView.bottomAnchor, constant: 2)
        ])
        
        /*titleView = UILabel()
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.font = .systemFont(ofSize: 28, weight: .semibold)
        titleView.textColor = .white
        titleView.text = lang("Scan QR Code")
        addSubview(titleView)
        NSLayoutConstraint.activate([
            titleView.bottomAnchor.constraint(equalTo: focusView.topAnchor, constant: -44),
            titleView.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])*/

        camera = Camera(configuration: .init(preset: .hd1920x1080, position: .back, audio: false))

        torchButton = GlassButton(icon: UIImage(named: "FlashIcon", in: AirBundle, compatibleWith: nil)!)
        addSubview(torchButton)
        NSLayoutConstraint.activate([
            torchButton.widthAnchor.constraint(equalToConstant: 72),
            torchButton.heightAnchor.constraint(equalToConstant: 72),
            torchButton.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0),
            torchButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 246)
        ])
        torchButton.addTarget(self, action: #selector(torchPressed), for: .touchUpInside)
        torchButton.isHidden = !camera.isTorchAvailable
        torchButton.isEnabled = camera.isTorchAvailable
    }

    private func setupCamera() {
        self.camera.attachPreviewNode(previewView)
        self.camera.startCapture()
        
        codesTask = Task { [weak self] in
            guard let self else {
                return
            }
            for await codes in self.camera.detectedCodes {
                guard !Task.isCancelled else {
                    break
                }
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.handleDetectedCodes(codes)
                }
            }
        }
    }
    
    @MainActor
    private func handleDetectedCodes(_ codes: [CameraCode]) {
        if shouldThrottleCodeDelivery() {
            return
        }
        
        if let code = codes.first, CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4).contains(code.boundingBox.center) {
            updateFocusedRect(code.boundingBox)
            onCodeDetected?(code)
        } else {
            updateFocusedRect(nil)
            onCodeDetected?(nil)
        }
    }
    
    @MainActor
    private func shouldThrottleCodeDelivery() -> Bool {
        let now = Date()
        if let lastCodeDeliveryDate, now.timeIntervalSince(lastCodeDeliveryDate) < 0.3 {
            return true
        }
        lastCodeDeliveryDate = now
        return false
    }
    
    // MARK: - Called when focused rect change
    private func updateFocusedRect(_ rect: CGRect?) {

        if let rect {
            // found a focus
            let side = max(bounds.width * rect.width, bounds.height * rect.height) * 0.6
            let center = CGPoint(x: (1.0 - rect.center.y) * bounds.width, y: rect.center.x * bounds.height)
            let focusedRect = CGRect(x: center.x - side / 2.0, y: center.y - side / 2.0, width: side, height: side)
            
            if !focusViewConstraints.isEmpty {
                // first time focus rect found, disable default constraints and set frame constraints
                UIView.animate(withDuration: 0.4) { [weak self] in
                    guard let self else {
                        return
                    }

                    leftDimView.alpha = 1
                    topDimView.alpha = 1
                    rightDimView.alpha = 1
                    bottomDimView.alpha = 1
                    //titleView.alpha = 0
                    torchButton.alpha = 0

                    NSLayoutConstraint.deactivate(focusViewConstraints)
                    focusViewConstraints = []
                    focusViewLeftConstraint = focusView.leftAnchor.constraint(equalTo: leftAnchor, constant: focusedRect.minX)
                    focusViewTopConstraint = focusView.topAnchor.constraint(equalTo: topAnchor, constant: focusedRect.minY)
                    focusViewWidthConstraint = focusView.widthAnchor.constraint(equalToConstant: focusedRect.width)
                    focusViewHeightConstraint = focusView.heightAnchor.constraint(equalToConstant: focusedRect.height)
                    NSLayoutConstraint.activate([
                        focusViewLeftConstraint!,
                        focusViewTopConstraint!,
                        focusViewWidthConstraint!,
                        focusViewHeightConstraint!
                    ])

                    layoutIfNeeded()
                }
            } else {
                // update focus rect constraints
                UIView.animate(withDuration: 0.2) { [weak self] in
                    guard let self else {
                        return
                    }
                    focusViewLeftConstraint!.constant = focusedRect.minX
                    focusViewTopConstraint!.constant = focusedRect.minY
                    focusViewWidthConstraint!.constant = focusedRect.width
                    focusViewHeightConstraint!.constant = focusedRect.height
                    layoutIfNeeded()
                }
            }
        } else {
            // was on focused area, now reset to default view
            if focusViewConstraints.isEmpty {
                focusViewConstraints = defaultFocusAreaConstraints()

                // update focus rect
                UIView.animate(withDuration: 0.4) { [weak self] in
                    guard let self else {
                        return
                    }

                    leftDimView.alpha = 0.625
                    topDimView.alpha = 0.625
                    rightDimView.alpha = 0.625
                    bottomDimView.alpha = 0.625
                    //titleView.alpha = 1
                    torchButton.alpha = 1

                    NSLayoutConstraint.deactivate([
                        focusViewLeftConstraint!,
                        focusViewTopConstraint!,
                        focusViewWidthConstraint!,
                        focusViewHeightConstraint!
                    ])
                    NSLayoutConstraint.activate(focusViewConstraints)

                    layoutIfNeeded()
                }
            }
        }
    }
    
    @objc private func torchPressed() {
        guard camera.isTorchAvailable else {
            return
        }
        self.torchButton.isSelected = !torchButton.isSelected
        self.camera.setTorchActive(torchButton.isSelected)
    }
}

// MARK: - Generate a frame for focused area
private func generateFrameImage() -> UIImage? {
    return generateImage(CGSize(width: 64.0, height: 64.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(4.0)
        context.setLineCap(.round)
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 2.0, y: 2.0 + 26.0))
        path.addArc(tangent1End: CGPoint(x: 2.0, y: 2.0), tangent2End: CGPoint(x: 2.0 + 26.0, y: 2.0), radius: 6.0)
        path.addLine(to: CGPoint(x: 2.0 + 26.0, y: 2.0))
        context.addPath(path)
        context.strokePath()
        
        path.move(to: CGPoint(x: size.width - 2.0, y: 2.0 + 26.0))
        path.addArc(tangent1End: CGPoint(x: size.width - 2.0, y: 2.0), tangent2End: CGPoint(x: 2.0 + 26.0, y: 2.0), radius: 6.0)
        path.addLine(to: CGPoint(x: size.width - 2.0 - 26.0, y: 2.0))
        context.addPath(path)
        context.strokePath()
        
        path.move(to: CGPoint(x: 2.0, y: size.height - 2.0 - 26.0))
        path.addArc(tangent1End: CGPoint(x: 2.0, y: size.height - 2.0), tangent2End: CGPoint(x: 2.0 + 26.0, y: size.height - 2.0), radius: 6.0)
        path.addLine(to: CGPoint(x: 2.0 + 26.0, y: size.height - 2.0))
        context.addPath(path)
        context.strokePath()
        
        path.move(to: CGPoint(x: size.width - 2.0, y: size.height - 2.0 - 26.0))
        path.addArc(tangent1End: CGPoint(x: size.width - 2.0, y: size.height - 2.0), tangent2End: CGPoint(x: 2.0 + 26.0, y: size.height - 2.0), radius: 6.0)
        path.addLine(to: CGPoint(x: size.width - 2.0 - 26.0, y: size.height - 2.0))
        context.addPath(path)
        context.strokePath()
    })?.stretchableImage(withLeftCapWidth: 32, topCapHeight: 32)
}
