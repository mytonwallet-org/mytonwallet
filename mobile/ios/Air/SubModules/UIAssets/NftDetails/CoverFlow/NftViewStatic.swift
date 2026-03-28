//
//  NftViewStatic.swift
//  UIAssets
//
//  Created by nikstar on 18.08.2025.
//

import UIKit
import Kingfisher
import WalletCore


final class NftViewStatic: UIImageView {

    enum ImageState {
        case loading
        case loaded
        case unavailable
    }
    
    var nft: ApiNft?
    var onStateChange: ((ImageState) -> Void)?

    private var currentRequestID = UUID()
    
    convenience init() {
        self.init(frame: .zero)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.contentMode = .scaleAspectFit
    }
    
    func reset() {
        currentRequestID = UUID()
        nft = nil
        kf.cancelDownloadTask()
        image = nil
    }

    func configure(nft: ApiNft?) {
        guard nft != self.nft else { return }
        self.nft = nft
        currentRequestID = UUID()
        let requestID = currentRequestID

        kf.cancelDownloadTask()
        image = nil

        let candidateURLs = Self.candidateImageURLs(for: nft)
        guard !candidateURLs.isEmpty else {
            onStateChange?(.unavailable)
            return
        }

        onStateChange?(.loading)
        loadImage(from: candidateURLs, at: 0, requestID: requestID)
    }

    private func loadImage(from urls: [URL], at index: Int, requestID: UUID) {
        let url = urls[index]
        kf.setImage(
            with: .network(url),
            placeholder: nil,
            options: [.alsoPrefetchToMemory, .cacheOriginalImage]
        ) { [weak self] result in
            guard let self, self.currentRequestID == requestID else { return }
            switch result {
            case .success:
                self.onStateChange?(.loaded)
            case .failure(let error):
                if error.isTaskCancelled {
                    return
                }
                let nextIndex = index + 1
                if urls.indices.contains(nextIndex) {
                    self.loadImage(from: urls, at: nextIndex, requestID: requestID)
                } else {
                    self.image = nil
                    self.onStateChange?(.unavailable)
                }
            }
        }
    }

    private static func candidateImageURLs(for nft: ApiNft?) -> [URL] {
        var seen = Set<String>()
        return [nft?.thumbnail, nft?.image]
            .compactMap(validatedURL(from:))
            .filter { seen.insert($0.absoluteString).inserted }
    }

    private static func validatedURL(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let url = URL(string: trimmedValue),
              url.scheme?.isEmpty == false else {
            return nil
        }
        return url
    }
}



#if DEBUG
@available(iOS 18, *)
#Preview {
    let view = NftViewStatic()
    let _  = view.configure(nft: ApiNft.sample)
    view
}
#endif
