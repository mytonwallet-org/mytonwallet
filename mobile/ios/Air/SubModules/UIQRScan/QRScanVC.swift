import UIKit
import UIComponents
import WalletContext
import WalletCore
import AVFoundation

@MainActor
public final class QRScanVC: WViewController {
    private var recognizedInvalidStrings = Set<String>()
    private var callback: (@MainActor (_ result: ScanResult?) -> Void)?
    private var lastScannedString: String?
    private var scanTask: Task<Void, Never>?
    private var isDismissingWithResult = false
    private var isShowingScanView = false

    private lazy var qrScanView: QRScanView = {
        let qrScanView = QRScanView()
        qrScanView.translatesAutoresizingMaskIntoConstraints = false
        qrScanView.onCodeDetected = { [weak self] message in
            self?.handleDetectedCode(message)
        }
        return qrScanView
    }()

    private lazy var noAccessView: NoCameraAccessView = {
        NoCameraAccessView()
    }()

    public init(callback: @escaping @MainActor (_ result: ScanResult?) -> Void) {
        self.callback = callback
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Scan QR Code")
        addCloseNavigationItemIfNeeded()
        let textAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        navigationController?.navigationBar.titleTextAttributes = textAttributes
        view.backgroundColor = .black
        Task { [weak self] in
            guard let self else {
                return
            }
            await self.configureCameraAccess()
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.tintColor = .white
        if isShowingScanView {
            qrScanView.startRunningIfNeeded()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isShowingScanView {
            qrScanView.stopRunning()
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if (isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true) && !isDismissingWithResult {
            finish(with: nil)
        }
    }

    private func configureCameraAccess() async {
        if await isCameraAccessGranted() {
            showScanView()
        } else {
            showNoAccessView()
        }
    }

    private func isCameraAccessGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func showScanView() {
        isShowingScanView = true
        noAccessView.removeFromSuperview()
        if qrScanView.superview == nil {
            view.insertSubview(qrScanView, at: 0)
            NSLayoutConstraint.activate([
                qrScanView.leftAnchor.constraint(equalTo: view.leftAnchor),
                qrScanView.rightAnchor.constraint(equalTo: view.rightAnchor),
                qrScanView.topAnchor.constraint(equalTo: view.topAnchor),
                qrScanView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        qrScanView.startRunningIfNeeded()
    }

    private func showNoAccessView() {
        if isShowingScanView {
            qrScanView.stopRunning()
        }
        isShowingScanView = false
        if noAccessView.superview == nil {
            view.insertSubview(noAccessView, at: 0)
            NSLayoutConstraint.activate([
                noAccessView.leftAnchor.constraint(equalTo: view.leftAnchor),
                noAccessView.rightAnchor.constraint(equalTo: view.rightAnchor),
                noAccessView.topAnchor.constraint(equalTo: view.topAnchor),
                noAccessView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
    }

    private func handleDetectedCode(_ message: String?) {
        guard let message else {
            lastScannedString = nil
            scanTask?.cancel()
            scanTask = nil
            return
        }
        guard message != lastScannedString else {
            return
        }
        lastScannedString = message

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else {
                return
            }
            self.handleScannedString(message)
            self.scanTask = nil
        }
    }

    private func handleScannedString(_ string: String) {
        var result: ScanResult?

        let chains = ApiChain.allCases.filter { $0.isValidAddressOrDomain(string) }
        if !chains.isEmpty {
            result = .address(address: string, possibleChains: chains)
        } else if let url = URL(string: string) {
            result = .url(url: url)
        } else {
            if !recognizedInvalidStrings.contains(string) {
                recognizedInvalidStrings.insert(string)
                showAlert(error: ApiAnyDisplayError.invalidAddressFormat)
            }
            return
        }
        
        guard let result else {
            return
        }

        if navigationController?.viewControllers.count ?? 0 > 1 {
            finish(with: result)
            navigationController?.popViewController(animated: true)
        } else {
            isDismissingWithResult = true
            dismiss(animated: true) { [weak self] in
                self?.finish(with: result)
            }
        }
    }

    private func finish(with result: ScanResult?) {
        scanTask?.cancel()
        scanTask = nil
        guard let callback else {
            return
        }
        self.callback = nil
        callback(result)
    }
}
