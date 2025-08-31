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
import SwiftSignalKit
import AVFoundation

public class QRScanVC: WViewController {
    
    public enum ScanResult {
        case url(url: URL)
        case address(address: String, possibleChains: [ApiChain])
    }
    
    private var recognizedStrings: Set<String> = []
    
    // MARK: - Initializer
    private let callback: ((_ result: ScanResult) -> Void)
    public init(callback: @escaping ((_ result: ScanResult) -> Void)) {
        self.callback = callback
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.codeDisposable?.dispose()
        self.inForegroundDisposable?.dispose()
    }

    public override func loadView() {
        super.loadView()
    }

    private var noAccessView: NoCameraAccessView? = nil
    private var qrScanView: QRScanView? = nil
    
    private func setupViews() {
        title = lang("Scan QR Code")
        addCloseToNavBar(color: .white)
        let textAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
        navigationController?.navigationBar.titleTextAttributes = textAttributes

        view.backgroundColor = .black

        authorizeAccessToCamera()
    }

    private func authorizeAccessToCamera(completion: @escaping (_ granted: Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { response in
            Queue.mainQueue().async {
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
    
    private var codeDisposable: Disposable?
    private var inForegroundDisposable: Disposable?

    var inForeground: Signal<Bool, NoError> {
        return .single(true)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setupViews()
        self.inForegroundDisposable = (inForeground
        |> deliverOnMainQueue).start(next: { [weak self] inForeground in
            guard let self else {return}
            qrScanView?.updateInForeground(inForeground)
        })
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.navigationBar.tintColor = .white
    }
    
    private func showScanView() {
        noAccessView?.removeFromSuperview()

        qrScanView = QRScanView()
        qrScanView?.translatesAutoresizingMaskIntoConstraints = false

        view.insertSubview(qrScanView!, at: 0)
        NSLayoutConstraint.activate([
            qrScanView!.leftAnchor.constraint(equalTo: view.leftAnchor),
            qrScanView!.rightAnchor.constraint(equalTo: view.rightAnchor),
            qrScanView!.topAnchor.constraint(equalTo: view.topAnchor),
            qrScanView!.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.codeDisposable = (qrScanView!.focusedCode.get()
        |> map { code -> String? in
            return code?.message
        }
        |> distinctUntilChanged
        |> mapToSignal { code -> Signal<String?, NoError> in
            return .single(code) |> delay(0.5, queue: Queue.mainQueue())
        }).start(next: { [weak self] string in
            guard let self, let string else { return }
            
            var result: ScanResult

            let chains = availableChains.filter { $0.validate(address: string) }
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
            
            if navigationController?.viewControllers.count ?? 0 > 1 {
                callback(result)
                navigationController?.popViewController(animated: true)
            } else {
                dismiss(animated: true) { [weak self] in
                    guard let self else {return}
                    callback(result)
                }
            }
        })
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
    
}
