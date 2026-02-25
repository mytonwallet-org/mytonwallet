import Foundation
import AVFoundation

private final class CameraContext: @unchecked Sendable {
    private let queue: DispatchQueue
    private let session = AVCaptureSession()
    private let device: CameraDevice
    private let input = CameraInput()
    private let output = CameraOutput()
    private let initialConfiguration: Camera.Configuration
    private let onCodes: ([CameraCode]) -> Void
    
    var previewNode: CameraPreviewNode? {
        didSet {
            previewNode?.prepare()
        }
    }
    
    init(queue: DispatchQueue, configuration: Camera.Configuration, onCodes: @escaping ([CameraCode]) -> Void) {
        self.queue = queue
        self.initialConfiguration = configuration
        self.onCodes = onCodes
        
        self.device = CameraDevice()
        self.device.configure(for: self.session, position: configuration.position)
        
        self.session.beginConfiguration()
        self.session.sessionPreset = configuration.preset
        self.input.configure(for: self.session, device: self.device, audio: configuration.audio)
        self.output.configure(for: self.session)
        self.session.commitConfiguration()
        
        self.output.processSampleBuffer = { [weak self] sampleBuffer, _ in
            guard let self else {
                return
            }
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
               CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Video {
                self.previewNode?.enqueue(sampleBuffer)
            }
        }
        
        self.output.processCodes = { [weak self] codes in
            guard let self else {
                return
            }
            queue.async { [weak self] in
                self?.onCodes(codes)
            }
        }
    }
    
    func startCapture() {
        guard !self.session.isRunning else {
            return
        }
        
        self.session.startRunning()
    }
    
    func stopCapture(invalidate: Bool = false) {
        if invalidate {
            self.session.beginConfiguration()
            self.input.invalidate(for: self.session)
            self.output.invalidate(for: self.session)
            self.session.commitConfiguration()
        }
        
        self.session.stopRunning()
    }
    
    func focus(at point: CGPoint) {
        self.device.setFocusPoint(point, focusMode: .continuousAutoFocus, exposureMode: .continuousAutoExposure, monitorSubjectAreaChange: true)
    }
    
    func setFPS(_ fps: Float64) {
        self.device.fps = fps
    }
    
    func togglePosition() {
        self.session.beginConfiguration()
        self.input.invalidate(for: self.session)
        let targetPosition: Camera.Position
        if case .back = self.device.position {
            targetPosition = .front
        } else {
            targetPosition = .back
        }
        self.device.configure(for: self.session, position: targetPosition)
        self.input.configure(for: self.session, device: self.device, audio: self.initialConfiguration.audio)
        self.session.commitConfiguration()
    }
    
    func setTorchActive(_ active: Bool) {
        self.device.setTorchActive(active)
    }
    
    var isTorchAvailable: Bool {
        self.device.isTorchAvailable
    }
}

public final class Camera: @unchecked Sendable {
    public typealias Preset = AVCaptureSession.Preset
    public typealias Position = AVCaptureDevice.Position
    public typealias FocusMode = AVCaptureDevice.FocusMode
    public typealias ExposureMode = AVCaptureDevice.ExposureMode
    
    public struct Configuration {
        let preset: Preset
        let position: Position
        let audio: Bool
        
        public init(preset: Preset, position: Position, audio: Bool) {
            self.preset = preset
            self.position = position
            self.audio = audio
        }
    }
    
    private let queue = DispatchQueue(label: "org.mytonwallet.camera.queue", qos: .userInitiated)
    private let context: CameraContext
    private let detectedCodesStream: AsyncStream<[CameraCode]>
    private let detectedCodesContinuation: AsyncStream<[CameraCode]>.Continuation
    
    public init(configuration: Camera.Configuration = Configuration(preset: .hd1920x1080, position: .back, audio: true)) {
        let streamParts = Camera.makeCodesStream()
        self.detectedCodesStream = streamParts.stream
        self.detectedCodesContinuation = streamParts.continuation
        let codesContinuation = self.detectedCodesContinuation
        self.context = CameraContext(queue: self.queue, configuration: configuration) { codes in
            codesContinuation.yield(codes)
        }
    }
    
    deinit {
        let detectedCodesContinuation = self.detectedCodesContinuation
        queue.sync { [context, detectedCodesContinuation] in
            context.stopCapture(invalidate: true)
            detectedCodesContinuation.finish()
        }
    }
    
    public func startCapture() {
        queue.async { [context] in
            context.startCapture()
        }
    }
    
    public func stopCapture(invalidate: Bool = false) {
        queue.async { [context] in
            context.stopCapture(invalidate: invalidate)
        }
    }
    
    public func togglePosition() {
        queue.async { [context] in
            context.togglePosition()
        }
    }
    
    public func focus(at point: CGPoint) {
        queue.async { [context] in
            context.focus(at: point)
        }
    }
    
    public func setFPS(_ fps: Double) {
        queue.async { [context] in
            context.setFPS(fps)
        }
    }
    
    public func setTorchActive(_ active: Bool) {
        queue.async { [context] in
            context.setTorchActive(active)
        }
    }
    
    public var isTorchAvailable: Bool {
        queue.sync { [context] in
            context.isTorchAvailable
        }
    }
    
    public func attachPreviewNode(_ node: CameraPreviewNode) {
        queue.async { [context] in
            context.previewNode = node
        }
    }
    
    public var detectedCodes: AsyncStream<[CameraCode]> {
        return self.detectedCodesStream
    }
    
    private static func makeCodesStream() -> (stream: AsyncStream<[CameraCode]>, continuation: AsyncStream<[CameraCode]>.Continuation) {
        var continuation: AsyncStream<[CameraCode]>.Continuation?
        let stream = AsyncStream<[CameraCode]> { createdContinuation in
            continuation = createdContinuation
        }
        guard let continuation else {
            fatalError("Failed to create detected codes stream")
        }
        return (stream: stream, continuation: continuation)
    }
}
