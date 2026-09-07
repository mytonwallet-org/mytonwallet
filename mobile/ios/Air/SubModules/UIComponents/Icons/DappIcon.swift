import Kingfisher
import SwiftUI
import WalletContext

private let genericIcon = "DappGenericIcon"

public extension IconView {
    func config(withDappIconURL iconUrl: String?) {
        let fallbackImage = UIImage.airBundle(genericIcon)
        config(with: Configuration(
            image: fallbackImage,
            shape: .roundedSquare,
            backgroundColor: .air.secondaryFill
        ))
        guard let iconUrl = iconUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let url = URL(string: iconUrl) else { return }
        imageView.kf.setImage(
            with: url,
            placeholder: nil,
            options: [.transition(.fade(0.15)), .onFailureImage(fallbackImage)]
        )
    }
}

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
