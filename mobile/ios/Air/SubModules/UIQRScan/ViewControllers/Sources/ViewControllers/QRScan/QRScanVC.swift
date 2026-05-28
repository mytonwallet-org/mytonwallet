//
//  QRScanVC.swift
//  UIQRScan
//
//  Created by Sina on 5/13/23.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore
import AVFoundation

public class QRScanVC: WViewController {
    
    private var recognizedStrings: Set<String> = []
    
    private var callback: ((_ result: ScanResult?) -> ())?
    private var lastScannedString: String?
    private var messageHandlingTask: Task<Void, Never>?
    
    public init(callback: @escaping ((_ result: ScanResult?) -> Void)) {
        self.callback = callback
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        messageHandlingTask?.cancel()
        callback?(nil)
    }

    public override func loadView() {
        super.loadView()
    }

    private var noAccessView: NoCameraAccessView? = nil
    private var qrScanView: QRScanView? = nil
    
    private func setupViews() {
        title = lang("Scan QR Code")
        addCloseNavigationItemIfNeeded()
        let textAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        navigationController?.navigationBar.titleTextAttributes = textAttributes

        view.backgroundColor = .black

        authorizeAccessToCamera()
    }

    private func authorizeAccessToCamera(completion: @escaping (_ granted: Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { response in
            DispatchQueue.main.async {
                if response {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }

    private func authorizeAccessToCamera() {
        authorizeAccessToCamera(completion: { [weak self] granted in
            guard let self else {
                return
            }
            if granted {
                showScanView()
            } else {
                showNoAccessView()
            }
        })
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setupViews()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.navigationBar.tintColor = .white
    }
    
    private func showScanView() {
        noAccessView?.removeFromSuperview()

        qrScanView = QRScanView()
        qrScanView?.translatesAutoresizingMaskIntoConstraints = false
        qrScanView?.onCodeDetected = { [weak self] code in
            guard let self else {
                return
            }
            guard let message = code?.message else {
                self.lastScannedString = nil
                self.messageHandlingTask?.cancel()
                self.messageHandlingTask = nil
                return
            }
            guard message != self.lastScannedString else {
                return
            }
            self.lastScannedString = message
            
            self.messageHandlingTask?.cancel()
            self.messageHandlingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.handleScannedString(message)
                    self.messageHandlingTask = nil
                }
            }
        }

        view.insertSubview(qrScanView!, at: 0)
        NSLayoutConstraint.activate([
            qrScanView!.leftAnchor.constraint(equalTo: view.leftAnchor),
            qrScanView!.rightAnchor.constraint(equalTo: view.rightAnchor),
            qrScanView!.topAnchor.constraint(equalTo: view.topAnchor),
            qrScanView!.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

    }
    
    private func showNoAccessView() {
        if noAccessView == nil {
            noAccessView = NoCameraAccessView()
        }
        if noAccessView?.superview == nil {
            view.insertSubview(noAccessView!, at: 0)
            NSLayoutConstraint.activate([
                noAccessView!.leftAnchor.constraint(equalTo: view.leftAnchor),
                noAccessView!.rightAnchor.constraint(equalTo: view.rightAnchor),
                noAccessView!.topAnchor.constraint(equalTo: view.topAnchor),
                noAccessView!.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
    
    private func handleScannedString(_ string: String) {
        var result: ScanResult?

        let chains = ApiChain.allCases.filter { $0.isValidAddressOrDomain(string) }
        if chains.count > 0 {
            result = .address(address: string, possibleChains: chains)
        } else if let url = URL(string: string) {
            result = .url(url: url)
        } else {
            if !recognizedStrings.contains(string) {
                recognizedStrings.insert(string)
                showAlert(error: ApiAnyDisplayError.invalidAddressFormat)
            }
            return
        }
        
        guard let result else {
            return
        }
        
        if navigationController?.viewControllers.count ?? 0 > 1 {
            callback?(result)
            callback = nil
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true) { [weak self] in
                guard let self else {return}
                callback?(result)
                callback = nil
            }
        }
    }
}
