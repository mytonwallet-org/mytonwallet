import SwiftUI
import UIKit
import WalletCore
import WalletContext
import Kingfisher

public struct NftPreviewFlowRepresentable: UIViewRepresentable {
    public var nfts: [ApiNft]
    public var maxItems: Int
    public var maxRows: Int
    public var horAlignment: WrappingFlowView.Alignment
    
    static func heightForRowCount(_ count: Int) -> CGFloat { (28.0 + 8.0) * CGFloat(count) - 8.0 }
    
    public init(nfts: [ApiNft], maxItems: Int = 10, maxRows: Int = 3, horAlignment: WrappingFlowView.Alignment = .left) {
        self.nfts = nfts
        self.maxItems = maxItems
        self.maxRows = maxRows
        self.horAlignment = horAlignment
    }

    public func makeUIView(context: Context) -> NftPreviewFlow {
        let view = NftPreviewFlow()
        apply(to: view)
        return view
    }

    public func updateUIView(_ uiView: NftPreviewFlow, context: Context) {
        apply(to: uiView)
    }

    private func apply(to view: NftPreviewFlow) {
        view.maxItemCount = maxItems
        view.maxRowCount = maxRows
        view.items = nfts
        view.horAlignment = horAlignment
    }
}

public final class NftPreviewFlow: WrappingFlowView {
    
    public var items: [ApiNft] = [] {
        didSet {
            if items != oldValue {
                applyItems()
            }
        }
    }

    private func applyItems() {
        let views = items.map {
            let v = _NftView()
            v.configure(nft: $0)
            return v
        }

        setArrangedSubviews(views) { count in
            let label = UILabel()
            label.semanticContentAttribute = .forceLeftToRight
            label.text = lang("$more_nfts", arg1: count)
            label.font = .systemFont(ofSize: 14)
            label.textColor = .air.secondaryLabel
            label.numberOfLines = 1
            return label
        }
    }
}

private final class _NftView: UIView {
    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        semanticContentAttribute = .forceLeftToRight

        backgroundColor = .air.secondaryFill
        layer.cornerCurve = .continuous
        layer.cornerRadius = 8
        clipsToBounds = true

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = .air.thumbBackground

        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 28),
            thumbnailView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(nft: ApiNft) {
        titleLabel.text = nft.displayName
        if let thumbnail = nft.thumbnail, let url = URL(string: thumbnail)  {
            thumbnailView.kf.setImage(with: .network(url))
        } else {
            thumbnailView.image = nil
            thumbnailView.kf.cancelDownloadTask()
        }
        invalidateIntrinsicContentSize()
    }
}
