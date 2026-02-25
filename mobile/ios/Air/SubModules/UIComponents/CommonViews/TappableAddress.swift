import SwiftUI
import WalletCore
import WalletContext
import Perception

public struct AddressViewModel {
    let chain: ApiChain
    
    /// The address returned via API. We assume that the API always returns raw (hex) wallet addresses
    let apiAddress: String?
        
    /// Name from API. For now it can be: domain, well-known name, whatever. The lowest priority
    let apiName: String?
    
    /// Name defined on the device: my account name or saved account name. To update call `withLocalName()` inside `WithPerceptionTracking`.
    /// This value (if not nil) supersedes `apiName`
    let localName: String?
        
    /// Generally, a wallet address as a key (identifier) is used to save address info in the local storage. Here we can override this behavior
    let saveKey: String?
        
    public init(
        chain: ApiChain,
        apiAddress: String? = nil,
        apiName: String? = nil,
        localName: String? = nil,
        saveKey: String? = nil,
    ) {
        self.chain = chain
        self.apiAddress = apiAddress
        self.apiName = apiName
        self.localName = localName
        self.saveKey = saveKey
    }
    
    public static func fromTransaction(_ tx: ApiTransactionActivity, chain: ApiChain, addressKind: ApiTransactionActivity.AddressKind) -> AddressViewModel {
        let apiName = tx.metadata?.name?.nilIfEmpty
        let apiAddress = tx.getAddress(for: addressKind)?.nilIfEmpty ?? apiName
        return .init(
            chain: chain,
            apiAddress: apiAddress,
            apiName: apiAddress == apiName ? nil : apiName,
            localName: nil,
            saveKey: nil
        )
    }
    
    /// Must be called from inside `WithPerceptionTracking`.
    func withLocalName(account: AccountContext) -> AddressViewModel {
        var localName: String?
        if chain.isSupported {
            // search for my account first
            if let address {
                localName = account.getMyAccountName(chain: chain, address: address)
            }
            // then search for saved address (with custom key, if available)
            if localName == nil, let saveKey = effectiveSaveKey {
                localName = account.getSavedAddressName(chain: chain, saveKey: saveKey)
            }
        }
        return .init(
            chain: chain,
            apiAddress: apiAddress,
            apiName: apiName,
            localName: localName,
            saveKey: saveKey,
        )
    }
    
    var name: String? { localName ?? apiName }
    
    var address: String? { apiAddress }
    
    var addressToCopy: String? { apiAddress  }

    var effectiveSaveKey: String? { saveKey ?? apiAddress }
}

public struct TappableAddress: View {
    let account: AccountContext
    let model: AddressViewModel
    
    @State private var menuContext = MenuContext()
    
    public init(account: AccountContext, model: AddressViewModel) {
        self.account = account
        self.model = model
    }
        
    public var body: some View {
        WithPerceptionTracking {
            let model = self.model.withLocalName(account: account)
            let isMenuEnabled = model.addressToCopy != nil
            
            let text = model.name ?? model.address ?? ""
            let compact = (model.name == nil && text.count > 20) || text.count > 25

            let addr = Text(
                formatAddressAttributed(
                    text,
                    startEnd: compact,
                    primaryColor: WTheme.secondaryLabel
                )
            )
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                addr
                if isMenuEnabled {
                    Image.airBundle("ArrowUpDownSmall")
                        .foregroundColor(Color(WTheme.secondaryLabel))
                        .opacity(0.8)
                        .offset(y: 1)
                }
            }
            .menuSource(isEnabled: isMenuEnabled, menuContext: menuContext)
            .task(id: isMenuEnabled) {
                if isMenuEnabled {
                    menuContext.makeConfig = {
                        let currentModel = self.model.withLocalName(account: account)
                        return makeTappableAddressMenu(accountContext: account, addressModel: currentModel)()
                    }
                }
            }
        }
    }
}

public struct TappableAddressFull: View {
    
    var accountContext: AccountContext
    let model: AddressViewModel
    let compactAddressWithName: Bool
    
    @State private var menuContext = MenuContext()
    
    let openInBrowser: (URL) -> () = { url in
        AppActions.openInBrowser(url)
    }
    
    public init(accountContext: AccountContext,  model: AddressViewModel, compactAddressWithName: Bool = true) {
        self.accountContext = accountContext
        self.model = model
        self.compactAddressWithName = compactAddressWithName
    }
    
    private func text(forModel model: AddressViewModel) -> Text {
        let address = model.address ?? ""
        
        if let name = model.name {
            let nameText = Text(name)
            let separator = Text("\u{A0}·\u{A0}").foregroundColor(Color(WTheme.secondaryLabel))
            let addrText = Text(formatAddressAttributed(address, startEnd: compactAddressWithName, primaryColor: WTheme.secondaryLabel))
            return Text("\(nameText)\(separator)\(addrText)")
        }
        
        return Text(formatAddressAttributed(address, startEnd: false))
    }

    /// Returns an icon + space when image exists, or empty Text when not found.
    private func chainIconText(chain: ApiChain) -> Text {
        guard let image = UIImage.airBundleOptional("inline_chain_\(chain.rawValue)") else { return Text("") }
        let resized = image.resizedToFit(size: CGSize(width: 16, height: 16)).withRenderingMode(.alwaysTemplate)
        return Text(Image(uiImage: resized))
            .foregroundColor(Color(WTheme.secondaryLabel))
            .baselineOffset(-2)
            + Text(" ")
    }
    
    public var body: some View {
        WithPerceptionTracking {
            let model = self.model.withLocalName(account: accountContext)
            let isMenuEnabled = model.addressToCopy != nil
            
            let text = text(forModel: model)
            let chainIcon = chainIconText(chain: model.chain)
            
            Group {
                if isMenuEnabled {
                    let more = Text(Image.airBundle("ArrowUpDownSmall"))
                        .foregroundColor(Color(WTheme.secondaryLabel).opacity(0.8))
                        .baselineOffset(-1)
                    
                    Text("\(chainIcon)\(text) \(more)")
                } else {
                    Text("\(chainIcon)\(text)")
                }
            }
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .menuSource(menuContext: menuContext)
            .task(id: isMenuEnabled) {
                if isMenuEnabled {
                    menuContext.makeConfig = {
                        let currentModel = self.model.withLocalName(account: accountContext)
                        return makeTappableAddressMenu(accountContext: accountContext, addressModel: currentModel)()
                    }
                }
            }
        }
    }
}
