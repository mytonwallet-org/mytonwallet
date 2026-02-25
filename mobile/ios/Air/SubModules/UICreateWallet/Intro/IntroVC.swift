//
//  StartVC.swift
//  UICreateWallet
//
//  Created by Sina on 3/31/23.
//

import UIKit
import UIComponents
import SwiftUI
import WalletContext

public class IntroVC: CreateWalletBaseVC {

    let introModel: IntroModel
    
    public init(introModel: IntroModel) {
        self.introModel = introModel
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private var hostingController: UIHostingController<IntroView>!
    
    func setupViews() {
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        let longTap = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        longTap.minimumPressDuration = 5
        view.addGestureRecognizer(longTap)
    }

    func makeView() -> IntroView {
        return IntroView(introModel: introModel)
    }
    
    @objc func onLongPress(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.showDebugView()
        }
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    LocalizationSupport.shared.setLanguageCode("ru")
    return UINavigationController(rootViewController: IntroVC(introModel: IntroModel(network: .mainnet, password: nil)))
}
#endif
