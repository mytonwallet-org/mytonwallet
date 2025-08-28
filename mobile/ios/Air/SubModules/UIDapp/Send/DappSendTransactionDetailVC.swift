
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Ledger


class DappSendTransactionDetailVC: WViewController {
    
    private let message: ApiDappTransfer
    
    init(message: ApiDappTransfer) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var hostingController: UIHostingController<DappSendTransactionDetailView>? = nil
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    func makeView() -> DappSendTransactionDetailView {
        return DappSendTransactionDetailView(
            message: message,
            onScroll: { [weak self] y in self?.updateNavigationBarProgressiveBlur(y) }
        )
    }
    
    private func setupViews() {
        
        addNavigationBar(
            title: lang("Transfer Details"),
            closeIcon: true,
            addBackButton: { [weak self] in self?.navigationController?.popViewController(animated: true) },
        )
        navigationBarProgressiveBlurDelta = 10
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)

        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
}


#if DEBUG
//@available(iOS 18, *)
//#Preview {
//    let activity1 = ApiActivity.transaction(ApiTransactionActivity(id: "d", kind: "transaction", timestamp: 0, amount: -123456789, fromAddress: "foo", toAddress: "bar", comment: nil, encryptedComment: nil, fee: 12345, slug: TON_USDT_SLUG, isIncoming: false, normalizedAddress: nil, externalMsgHashNorm: nil, shouldHide: nil, type: nil, metadata: nil, nft: nil, isPending: nil))
//    let activity2 = ApiActivity.transaction(ApiTransactionActivity(id: "d2", kind: "transaction", timestamp: 0, amount: -456789, fromAddress: "foo", toAddress: "bar", comment: nil, encryptedComment: nil, fee: 12345, slug: TON_USDT_SLUG, isIncoming: false, normalizedAddress: nil, externalMsgHashNorm: nil, shouldHide: nil, type: .callContract, metadata: nil, nft: nil, isPending: nil))
//    let _ = UIFont.registerAirFonts()
//    
//    let request = MDappSendTransactions(
//        promiseId: "",
//        accountId: "",
//        dapp: ApiDapp(url: "dedust.io", name: "Dedust", iconUrl: "https://files.readme.io/681e2e6-dedust_1.png", manifestUrl: "", connectedAt: nil, isUrlEnsured: nil, sse: nil),
//        transactions: [
//            ApiDappTransfer(
//                toAddress: "tkfjkdfajlkfadjaflskdhdhladmfdfo",
//                amount: 123456789,
//                rawPayload: "adfsljhfdajlhfdasjkfhkjlhfdjkashfjadhkjdashfkjhafjfadshljkfahdsfadsjk",
//                isScam: true,
//                isDangerous: true,
//                normalizedAddress: "bar",
//                displayedToAddress: "fkkfkf",
//                networkFee: 132456
//            )
//        ],
//        emulation: Emulation(
//            activities: [activity1, activity2],
//            realFee: 123456
//        )
//    )
//    
//    DappSendTransactionDetailVC(message: request.transactions[0])
//}
#endif
