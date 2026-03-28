import UIKit
import UIComponents
import WalletContext
@preconcurrency import AVFoundation

@MainActor
final class QRScanView: UIView {
    var onCodeDetected: ((String?) -> Void)?

    private let previewView = PreviewView()
    private let scanner = QRCodeScanner()
    private let focusView = UIView()
    private let leftDimView = UIView()
    private let topDimView = UIView()
    private let rightDimView = UIView()
    private let bottomDimView = UIView()
    private let torchButton = GlassButton(icon: UIImage(named: "FlashIcon", in: AirBundle, compatibleWith: nil)!)
    private let clock = ContinuousClock()

    private var defaultFocusConstraints: [NSLayoutConstraint] = []
    private var trackedFocusConstraints: [NSLayoutConstraint] = []
    private var lastCodeDeliveryDate: ContinuousClock.Instant?

    init() {
        super.init(frame: .zero)
        setupViews()
        scanner.attach(to: previewView.previewLayer)
        scanner.onCodeDetected = { [weak self] code in
            self?.handleDetectedCode(code)
        }
        scanner.onTorchAvailabilityChanged = { [weak self] isAvailable in
            self?.updateTorchAvailability(isAvailable)
        }
        updateTorchAvailability(scanner.isTorchAvailable)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startRunningIfNeeded() {
        scanner.startRunningIfNeeded()
    }

    func stopRunning() {
        torchButton.isSelected = false
        scanner.stopRunning()
    }

    private func setupViews() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.backgroundColor = .black
        addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.leftAnchor.constraint(equalTo: leftAnchor),
            previewView.rightAnchor.constraint(equalTo: rightAnchor),
            previewView.topAnchor.constraint(equalTo: topAnchor),
            previewView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        focusView.translatesAutoresizingMaskIntoConstraints = false
        focusView.backgroundColor = .clear
        addSubview(focusView)
        defaultFocusConstraints = makeDefaultFocusConstraints()
        NSLayoutConstraint.activate(defaultFocusConstraints)

        for dimView in [topDimView, bottomDimView, leftDimView, rightDimView] {
            dimView.translatesAutoresizingMaskIntoConstraints = false
            dimView.alpha = 0.625
            dimView.backgroundColor = .black.withAlphaComponent(0.8)
            addSubview(dimView)
        }

        NSLayoutConstraint.activate([
            topDimView.leftAnchor.constraint(equalTo: leftAnchor),
            topDimView.rightAnchor.constraint(equalTo: rightAnchor),
            topDimView.topAnchor.constraint(equalTo: topAnchor),
            topDimView.bottomAnchor.constraint(equalTo: focusView.topAnchor),

            bottomDimView.leftAnchor.constraint(equalTo: leftAnchor),
            bottomDimView.rightAnchor.constraint(equalTo: rightAnchor),
            bottomDimView.topAnchor.constraint(equalTo: focusView.bottomAnchor),
            bottomDimView.bottomAnchor.constraint(equalTo: bottomAnchor),

            leftDimView.leftAnchor.constraint(equalTo: leftAnchor),
            leftDimView.rightAnchor.constraint(equalTo: focusView.leftAnchor),
            leftDimView.topAnchor.constraint(equalTo: focusView.topAnchor),
            leftDimView.bottomAnchor.constraint(equalTo: focusView.bottomAnchor),

            rightDimView.leftAnchor.constraint(equalTo: focusView.rightAnchor),
            rightDimView.rightAnchor.constraint(equalTo: rightAnchor),
            rightDimView.topAnchor.constraint(equalTo: focusView.topAnchor),
            rightDimView.bottomAnchor.constraint(equalTo: focusView.bottomAnchor),
        ])

        let frameView = UIImageView()
        frameView.translatesAutoresizingMaskIntoConstraints = false
        frameView.image = generateFrameImage()
        addSubview(frameView)
        NSLayoutConstraint.activate([
            frameView.leftAnchor.constraint(equalTo: focusView.leftAnchor, constant: -2),
            frameView.rightAnchor.constraint(equalTo: focusView.rightAnchor, constant: 2),
            frameView.topAnchor.constraint(equalTo: focusView.topAnchor, constant: -2),
            frameView.bottomAnchor.constraint(equalTo: focusView.bottomAnchor, constant: 2),
        ])

        addSubview(torchButton)
        NSLayoutConstraint.activate([
            torchButton.widthAnchor.constraint(equalToConstant: 72),
            torchButton.heightAnchor.constraint(equalToConstant: 72),
            torchButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            torchButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 246),
        ])
        torchButton.addTarget(self, action: #selector(torchPressed), for: .touchUpInside)
    }

    private func makeDefaultFocusConstraints() -> [NSLayoutConstraint] {
        [
            focusView.widthAnchor.constraint(equalToConstant: 260),
            focusView.heightAnchor.constraint(equalToConstant: 260),
            focusView.centerXAnchor.constraint(equalTo: centerXAnchor),
            focusView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
    }

    private func handleDetectedCode(_ code: DetectedCode?) {
        guard !shouldThrottleCodeDelivery() else {
            return
        }

        guard let code, detectionArea.contains(code.frame.center) else {
            updateFocusedRect(nil)
            onCodeDetected?(nil)
            return
        }

        updateFocusedRect(code.frame)
        onCodeDetected?(code.message)
    }

    private func shouldThrottleCodeDelivery() -> Bool {
        let now = clock.now
        if let lastCodeDeliveryDate, now - lastCodeDeliveryDate < .milliseconds(300) {
            return true
        }
        lastCodeDeliveryDate = now
        return false
    }

    private var detectionArea: CGRect {
        CGRect(
            x: bounds.width * 0.3,
            y: bounds.height * 0.3,
            width: bounds.width * 0.4,
            height: bounds.height * 0.4
        )
    }

    private func updateFocusedRect(_ rect: CGRect?) {
        guard let rect else {
            resetFocusedRect()
            return
        }

        let side = max(rect.width, rect.height) * 0.6
        let focusedRect = CGRect(
            x: rect.midX - side / 2.0,
            y: rect.midY - side / 2.0,
            width: side,
            height: side
        ).clamped(to: bounds)

        if trackedFocusConstraints.isEmpty {
            UIView.animate(withDuration: 0.4) {
                self.leftDimView.alpha = 1
                self.topDimView.alpha = 1
                self.rightDimView.alpha = 1
                self.bottomDimView.alpha = 1
                self.torchButton.alpha = 0

                NSLayoutConstraint.deactivate(self.defaultFocusConstraints)
                self.trackedFocusConstraints = self.makeTrackedFocusConstraints(for: focusedRect)
                NSLayoutConstraint.activate(self.trackedFocusConstraints)
                self.layoutIfNeeded()
            }
            return
        }

        UIView.animate(withDuration: 0.2) {
            self.trackedFocusConstraints[0].constant = focusedRect.minX
            self.trackedFocusConstraints[1].constant = focusedRect.minY
            self.trackedFocusConstraints[2].constant = focusedRect.width
            self.trackedFocusConstraints[3].constant = focusedRect.height
            self.layoutIfNeeded()
        }
    }

    private func resetFocusedRect() {
        guard !trackedFocusConstraints.isEmpty else {
            return
        }

        defaultFocusConstraints = makeDefaultFocusConstraints()
        UIView.animate(withDuration: 0.4) {
            self.leftDimView.alpha = 0.625
            self.topDimView.alpha = 0.625
            self.rightDimView.alpha = 0.625
            self.bottomDimView.alpha = 0.625
            self.torchButton.alpha = 1

            NSLayoutConstraint.deactivate(self.trackedFocusConstraints)
            self.trackedFocusConstraints.removeAll()
            NSLayoutConstraint.activate(self.defaultFocusConstraints)
            self.layoutIfNeeded()
        }
    }

    private func makeTrackedFocusConstraints(for rect: CGRect) -> [NSLayoutConstraint] {
        [
            focusView.leftAnchor.constraint(equalTo: leftAnchor, constant: rect.minX),
            focusView.topAnchor.constraint(equalTo: topAnchor, constant: rect.minY),
            focusView.widthAnchor.constraint(equalToConstant: rect.width),
            focusView.heightAnchor.constraint(equalToConstant: rect.height),
        ]
    }

    private func updateTorchAvailability(_ isAvailable: Bool) {
        torchButton.isHidden = !isAvailable
        torchButton.isEnabled = isAvailable
    }

    @objc private func torchPressed() {
        guard scanner.isTorchAvailable else {
            return
        }
        torchButton.isSelected.toggle()
        scanner.setTorchActive(torchButton.isSelected)
    }
}

@MainActor private func generateFrameImage() -> UIImage? {
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

private struct DetectedCode {
    let message: String
    let frame: CGRect
}

private final class QRCodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    var onCodeDetected: ((DetectedCode?) -> Void)?
    var onTorchAvailabilityChanged: ((Bool) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "org.mytonwallet.qrscan.session", qos: .userInitiated)
    private let metadataOutput = AVCaptureMetadataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false

    @MainActor
    func attach(to previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    func startRunningIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            guard self.configureIfNeeded(), !self.session.isRunning else {
                return
            }
            self.session.startRunning()
        }
    }

    func stopRunning() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.setTorchActiveIfNeeded(false)
            guard self.session.isRunning else {
                return
            }
            self.session.stopRunning()
        }
    }

    var isTorchAvailable: Bool {
        sessionQueue.sync {
            videoInput?.device.hasTorch == true
        }
    }

    func setTorchActive(_ isActive: Bool) {
        sessionQueue.async { [weak self] in
            self?.setTorchActiveIfNeeded(isActive)
        }
    }

    private func configureIfNeeded() -> Bool {
        guard !isConfigured else {
            return true
        }
        guard let device = AVCaptureDevice.default(for: .video) else {
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.sessionPreset = .hd1920x1080

            guard session.canAddInput(input), session.canAddOutput(metadataOutput) else {
                session.commitConfiguration()
                return false
            }

            session.addInput(input)
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)
            guard metadataOutput.availableMetadataObjectTypes.contains(.qr) else {
                session.commitConfiguration()
                return false
            }

            metadataOutput.metadataObjectTypes = [.qr]
            session.commitConfiguration()

            videoInput = input
            isConfigured = true
            notifyTorchAvailabilityChanged()
            return true
        } catch {
            return false
        }
    }

    private func setTorchActiveIfNeeded(_ isActive: Bool) {
        guard let device = videoInput?.device, device.hasTorch else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = isActive ? .on : .off
            device.unlockForConfiguration()
        } catch {
        }
    }

    private func notifyTorchAvailabilityChanged() {
        let isAvailable = videoInput?.device.hasTorch == true
        DispatchQueue.main.async { [weak self] in
            self?.onTorchAvailabilityChanged?(isAvailable)
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard
            let codeObject = metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .first(where: { $0.type == .qr && !($0.stringValue?.isEmpty ?? true) }),
            let message = codeObject.stringValue
        else {
            DispatchQueue.main.async { [weak self] in
                self?.onCodeDetected?(nil)
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                let previewLayer = self.previewLayer,
                let transformedObject = previewLayer.transformedMetadataObject(for: codeObject) as? AVMetadataMachineReadableCodeObject
            else {
                self?.onCodeDetected?(nil)
                return
            }

            self.onCodeDetected?(DetectedCode(message: message, frame: transformedObject.bounds))
        }
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
