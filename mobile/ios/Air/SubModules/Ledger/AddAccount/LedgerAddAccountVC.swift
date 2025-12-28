
import UIComponents
import WalletContext
import UIKit
import SwiftUI


public final class LedgerAddAccountVC: WViewController {
    
    public var onDone: ((LedgerAddAccountVC) -> ())?
    
    let showBackButton: Bool
    var hostingController: UIHostingController<LedgerAddAccountView>? = nil
    var model: LedgerAddAccountModel
    
    public init(model: LedgerAddAccountModel, showBackButton: Bool) {
        self.model = model
        self.showBackButton = showBackButton
        super.init(nibName: nil, bundle: nil)
        model.onDone = { [weak self] in self?.handleOnDone() }
        model.onCancel = { [weak self] in self?.handleOnCancel() }
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private func setupViews() {
        
        let cancelItem: WNavigationBarButton? = showBackButton ? nil : .init(text: lang("Cancel"), onPress: { [weak self] in self?.presentingViewController?.dismiss(animated: true) })
        let backAction: (() -> ())? = showBackButton ? { [weak self] in self?.navigationController?.popViewController(animated: true) } : nil
        addNavigationBar(
            title: lang("Connect Ledger"),
            leadingItem: cancelItem,
            addBackButton: backAction
        )
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    private func makeView() -> LedgerAddAccountView {
        LedgerAddAccountView(viewModel: self.model.viewModel)
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.start()
    }
    
    private func handleOnDone() {
        onDone?(self)
    }
    
    private func handleOnCancel() {
        navigationController?.popViewController(animated: true)
    }
}
