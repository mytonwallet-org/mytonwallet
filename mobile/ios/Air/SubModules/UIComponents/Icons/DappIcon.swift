import Kingfisher
import SwiftUI
import WalletContext

private let genericIcon = "DappGenericIcon"

public struct DappIcon: View {
    
    let iconUrl: String?
    
    public init(iconUrl: String?) {
        self.iconUrl = iconUrl
    }
    
    public var body: some View {
        if let iconUrl = normalizedIconUrl, let url = URL(string: iconUrl) {
            KFImage(url)
                .placeholder {
                    Color.air.secondaryFill
                }
                .onFailureImage(UIImage.airBundle(genericIcon))
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
        } else {
            Image.airBundle(genericIcon)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
    
    private var normalizedIconUrl: String? {
        iconUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}
