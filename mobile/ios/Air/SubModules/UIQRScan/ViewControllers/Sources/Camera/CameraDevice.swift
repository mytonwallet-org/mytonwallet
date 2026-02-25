import Foundation
import AVFoundation

private let defaultFPS: Double = 30.0

final class CameraDevice {
    public private(set) var videoDevice: AVCaptureDevice? = nil
    public private(set) var audioDevice: AVCaptureDevice? = nil
    
    init() {
    }
    
    var position: Camera.Position = .back
    var isTorchAvailable: Bool {
        guard let device = self.videoDevice else {
            return false
        }
        return device.hasTorch && device.isTorchModeSupported(.on)
    }
    
    func configure(for session: AVCaptureSession, position: Camera.Position) {
        self.position = position
        self.videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera, .builtInTelephotoCamera], mediaType: .video, position: position).devices.first
        self.audioDevice = AVCaptureDevice.default(for: .audio)
    }
    
    func transaction(_ device: AVCaptureDevice, update: (AVCaptureDevice) -> Void) {
        if let _ = try? device.lockForConfiguration() {
            update(device)
            device.unlockForConfiguration()
        }
    }
    
    var fps: Double = defaultFPS {
        didSet {
            guard let device = self.videoDevice, let targetFPS = device.actualFPS(Double(self.fps)) else {
                return
            }
            
            self.fps = targetFPS.fps
            
            self.transaction(device) { device in
                device.activeVideoMinFrameDuration = targetFPS.duration
                device.activeVideoMaxFrameDuration = targetFPS.duration
            }
        }
    }
    
    func setFocusPoint(_ point: CGPoint, focusMode: Camera.FocusMode, exposureMode: Camera.ExposureMode, monitorSubjectAreaChange: Bool) {
        guard let device = self.videoDevice else {
            return
        }
        self.transaction(device) { device in
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                device.exposurePointOfInterest = point
                device.exposureMode = exposureMode
            }
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                device.focusPointOfInterest = point
                device.focusMode = focusMode
            }
        }
    }
    
    func setExposureTargetBias(_ bias: Float) {
        guard let device = self.videoDevice else {
            return
        }
        self.transaction(device) { device in
            let extremum = (bias >= 0) ? device.maxExposureTargetBias : device.minExposureTargetBias;
            let value = abs(bias) * extremum * 0.85
            device.setExposureTargetBias(value, completionHandler: nil)
        }
    }
    
    func setTorchActive(_ active: Bool) {
        guard let device = self.videoDevice, self.isTorchAvailable else {
            return
        }
        self.transaction(device) { device in
            device.torchMode = active ? .on : .off
        }
    }
}
