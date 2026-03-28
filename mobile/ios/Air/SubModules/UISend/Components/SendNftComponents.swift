import SwiftUI
import Dependencies
import WalletContext
import Perception
import UIComponents

internal struct NftSection: View {
    let model: SendModel
    
    var body: some View {
        WithPerceptionTracking {
            let nfts = model.nfts
            if nfts.count > 0 {
                InsetSection {
                    if nfts.count == 1 {
                        NftPreviewRow(nft: nfts[0])
                    } else {
                        InsetCell(verticalPadding: 16) {
                            NftPreviewFlowRepresentable(
                                nfts: nfts,
                                maxItems: 10,
                                maxRows: 6
                            )
                        }
                    }
                }
            }
        }
    }
}

class BurnNftWarningTile: UIView {
    private let textLabel = UILabel()
    private var widthConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        backgroundColor = .air.error.withAlphaComponent(0.12)
        layer.cornerCurve = .continuous
        layer.cornerRadius = 10
        layer.masksToBounds = true
        
        let band = UIView()
        band.backgroundColor = .air.error
        band.translatesAutoresizingMaskIntoConstraints = false
        addSubview(band)
        
        textLabel.text = lang("Are you sure you want to burn this NFT? It will be lost forever.")
        textLabel.textColor = .air.error
        textLabel.font = .systemFont(ofSize: 14, weight: .medium)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        addSubview(textLabel)

        widthConstraint = widthAnchor.constraint(equalToConstant: 100)
        
        NSLayoutConstraint.activate([
            band.leadingAnchor.constraint(equalTo: leadingAnchor),
            band.topAnchor.constraint(equalTo: topAnchor),
            band.bottomAnchor.constraint(equalTo: bottomAnchor),
            band.widthAnchor.constraint(equalToConstant: 4),
            
            textLabel.leadingAnchor.constraint(equalTo: band.trailingAnchor, constant: 12),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            widthConstraint
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let textSize = textLabel.sizeThatFits(.init(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        widthConstraint.constant = min(300, textSize.width + 32)
    }
}

internal struct NftFeeSection: View {
    let model: SendModel
    
    @Dependency(\.tokenStore) private var tokenStore
    
    var feeText: String? {
        let nativeToken = tokenStore.getNativeToken(chain: model.token.chain)
        let fee = model.showingFee
        return fee?.toString(token: model.token, nativeToken: nativeToken)
    }
        
    var body: some View {
        WithPerceptionTracking {
            if let feeText {
                InsetSection {
                    InsetCell(verticalPadding: 16) {
                        Text("\(feeText)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                header: {
                    Text(lang("Fee"))
                }
            }
        }
    }
}
