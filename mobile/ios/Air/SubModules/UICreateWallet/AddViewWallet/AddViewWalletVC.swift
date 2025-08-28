
import UIKit
import SwiftUI
import UIPasscode
import UIComponents
import WalletCore
import WalletContext


public class AddViewWalletVC: WViewController, WKeyboardObserverDelegate {

    private var headerView: HeaderView!
    private var hostingController: UIHostingController<AddViewWalletView>?
    private var continueButton: WButton { self.bottomButton! }
    private var continueButtonConstraint: NSLayoutConstraint?
    private var value: String = ""
    
    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    func setupViews() {
        addNavigationBar(
            title: "",
            closeIcon: AccountStore.accountsById.count > 0,
            addBackButton: (navigationController?.viewControllers.count ?? 1) > 1 ? { [weak self] in
                guard let self else {return}
                navigationController?.popViewController(animated: true)
            } : nil)

        // header
        headerView = HeaderView(
            animationName: "Recovery Phrase",
            animationPlaybackMode: .once,
            title: lang("View Any Address"),
            description: nil
        )
        view.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        let hc = addHostingController(makeView())
        self.hostingController = hc
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
        hc.sizingOptions = [.intrinsicContentSize, .preferredContentSize]

        _ = addBottomButton(bottomConstraint: false)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        
        let c = false ? -max(WKeyboardObserver.keyboardHeight, 291) + 50 : -34
        let constraint = continueButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16 + c)
        constraint.isActive = true
        self.continueButtonConstraint = constraint
        
        bringNavigationBarToFront()
        WKeyboardObserver.observeKeyboard(delegate: self)
        updateTheme()
        onChange("")
    }
    
    func makeView() -> AddViewWalletView {
        AddViewWalletView(onChange: { [weak self] in self?.onChange($0) }, onSumit: continuePressed)
    }
    
    public override func updateTheme() {
    }
    
    func onChange(_ value: String) {
        self.value = value
        continueButton.setTitle(lang("Continue"), for: .normal)
        continueButton.isEnabled = !value.isEmpty
    }
    
    @objc func continuePressed() {
        if let value = self.value.nilIfEmpty {
            Task {
                await handleAddAddress(value)
            }
        }
    }
    
    func handleAddAddress(_ address: String) async {
        do {
            let chain: ApiChain = value.starts(with: "T") ? .tron : .ton
            let ton = chain == .ton ? address : nil
            let tron = chain == .tron ? address : nil
            _ = try await AccountStore.importViewWallet(network: .mainnet, tonAddress: ton, tronAddress: tron)
            self.presentingViewController?.dismiss(animated: true)
        } catch {
            if let error = error as? BridgeCallError {
                switch error {
                case .apiReturnedError(let error, _):
                    if let errorMessage = BridgeCallErrorMessages(rawValue: error) {
                        continueButton.setTitle(errorMessage.toLocalized, for: .normal)
                        continueButton.isEnabled = false
                        return
                    }
                    break
                default:
                    break
                }
            }
            showAlert(error: error)
        }
    }

    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) { [self] in
            if let continueButtonConstraint {
                continueButtonConstraint.constant = -info.height - 16
                view.layoutIfNeeded()
            }
        }
    }
    
    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) { [self] in
            if let continueButtonConstraint {
                continueButtonConstraint.constant =  -view.safeAreaInsets.bottom - 16
                view.layoutIfNeeded()
            }
        }
    }
}
