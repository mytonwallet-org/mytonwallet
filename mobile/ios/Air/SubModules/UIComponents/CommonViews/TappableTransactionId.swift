
import ContextMenuKit
import SwiftUI
import UIKit
import WalletCore
import WalletContext

public struct TappableTransactionId: View {
    
    var chain: ApiChain
    var txId: String
    
    public init(chain: ApiChain, txId: String) {
        self.chain = chain
        self.txId = txId
    }
    
    public var body: some View {
        
        let tx: Text = Text(
            formatStartEndAddress(txId)
        )
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            tx
            Image.airBundle("ArrowUpDownSmall")
                .foregroundColor(Color.air.secondaryLabel)
                .opacity(0.8)
                .offset(y: 1)
        }
        .contextMenuSource {
            makeMenuConfiguration()
        }
        .foregroundStyle(Color.air.primaryLabel)
    }

    private func makeMenuConfiguration() -> ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(
                    ContextMenuAction(
                        title: lang("Copy"),
                        icon: .airBundle("SendCopy"),
                        handler: {
                            UIPasteboard.general.string = txId
                            AppActions.showToast(icon: .animatedCopy, message: lang("Transaction ID Copied"))
                            Haptics.play(.lightTap)
                        }
                    )
                ),
                .action(
                    ContextMenuAction(
                        title: lang("Open in Explorer"),
                        icon: .airBundle("SendGlobe"),
                        handler: {
                            let url = ExplorerHelper.txUrl(chain: chain, txHash: txId)
                            AppActions.openInBrowser(url)
                        }
                    )
                ),
            ]),
            backdrop: .none
        )
    }
}

    
public struct SwapProviderTransactionId: View {
    
    var id: String
    var trackingUrl: URL?
    
    public init(id: String, trackingUrl: URL? = nil) {
        self.id = id
        self.trackingUrl = trackingUrl
    }
    
    public var body: some View {
        
        let tx: Text = Text(
            formatStartEndAddress(id)
        )
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            tx
            Image.airBundle("ArrowUpDownSmall")
                .foregroundColor(Color.air.secondaryLabel)
                .opacity(0.8)
                .offset(y: 1)
        }
        .foregroundStyle(Color.air.primaryLabel)
        .contextMenuSource {
            makeMenuConfiguration()
        }
    }

    private func makeMenuConfiguration() -> ContextMenuConfiguration {
        var items: [ContextMenuItem] = [
            .action(
                ContextMenuAction(
                    title: lang("Copy Swap ID"),
                    icon: .airBundle("SendCopy"),
                    handler: {
                        UIPasteboard.general.string = id
                        AppActions.showToast(icon: .animatedCopy, message: lang("Swap ID Copied"))
                        Haptics.play(.lightTap)
                    }
                )
            )
        ]

        if let trackingUrl {
            items.append(
                .action(
                    ContextMenuAction(
                        title: lang("Open in Explorer"),
                        icon: .airBundle("SendGlobe"),
                        handler: {
                            AppActions.openInBrowser(trackingUrl)
                        }
                    )
                )
            )
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .none
        )
    }
}

public struct CopyableAddressText: View {

    var address: String
    var copyToastMessage: String

    public init(address: String, copyToastMessage: String) {
        self.address = address
        self.copyToastMessage = copyToastMessage
    }

    public var body: some View {
        let addressFont = UIFont.systemFont(ofSize: 17, weight: .regular)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(formatAddressAttributed(
                address,
                startEnd: true,
                primaryFont: addressFont,
                secondaryFont: addressFont
            ))
            Image.airBundle("ArrowUpDownSmall")
                .foregroundColor(Color.air.secondaryLabel)
                .opacity(0.8)
                .offset(y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(.rect)
        .foregroundStyle(Color.air.primaryLabel)
        .contextMenuSource {
            makeMenuConfiguration()
        }
    }

    private func makeMenuConfiguration() -> ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(
                    ContextMenuAction(
                        title: lang("Copy Address"),
                        icon: .airBundle("SendCopy"),
                        handler: {
                            UIPasteboard.general.string = address
                            AppActions.showToast(icon: .animatedCopy, message: copyToastMessage)
                            Haptics.play(.lightTap)
                        }
                    )
                ),
            ]),
            backdrop: .none
        )
    }
}
