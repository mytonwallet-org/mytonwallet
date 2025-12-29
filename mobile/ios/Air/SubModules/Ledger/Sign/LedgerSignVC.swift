
import UIKit
import SwiftUI
import UIComponents
import WalletContext


public final class LedgerSignVC<HeaderView: View>: WViewController {
    
    public var onDone: ((LedgerSignVC<HeaderView>) -> ())?
    public var onCancel: ((LedgerSignVC<HeaderView>) -> ())?
    
    var headerView: HeaderView
    var hostingController: UIHostingController<LedgerSignView<HeaderView>>? = nil
    var model: LedgerSignModel
    
    public init(model: LedgerSignModel, title: String?, headerView: HeaderView) {
        self.model = model
        self.headerView = headerView
        super.init(nibName: nil, bundle: nil)
        self.title = title
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
        addNavigationBar(
            title: title ?? "Confirm with Ledger",
            closeIcon: true,
            addBackButton: { [weak self] in self?.navigationController?.popViewController(animated: true) }
        )
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    private func makeView() -> LedgerSignView<HeaderView> {
        LedgerSignView(headerView: self.headerView, viewModel: self.model.viewModel)
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
        if let onCancel = self.onCancel {
            onCancel(self)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}

