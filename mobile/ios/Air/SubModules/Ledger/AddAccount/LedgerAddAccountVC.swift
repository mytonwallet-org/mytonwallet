
import UIComponents
import WalletContext
import UIKit
import SwiftUI


public final class LedgerAddAccountVC: WViewController {
    
    public var onDone: ((LedgerAddAccountVC) -> ())?
    
    private var hostingController: UIHostingController<LedgerAddAccountView>? = nil
    private var model: LedgerAddAccountModel
    private var initialDelay: Bool
    
    public init(model: LedgerAddAccountModel, autoStart: Bool = true) {
        self.model = model
        self.initialDelay = !autoStart
        
        super.init(nibName: nil, bundle: nil)
        
        model.onDone = { [weak self] in self?.handleOnDone() }
        model.onCancel = { [weak self] in self?.handleOnCancel() }
        
        title = lang("Connect Ledger")
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        updateTheme()
    }
    
    private func makeView() -> LedgerAddAccountView {
        LedgerAddAccountView(viewModel: model.viewModel)
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !initialDelay {
            model.start()
        }
        initialDelay = false
    }
    
    public func start() {
        model.start()
    }
    
    private func handleOnDone() {
        onDone?(self)
    }
    
    private func handleOnCancel() {
        if canGoBack {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}
