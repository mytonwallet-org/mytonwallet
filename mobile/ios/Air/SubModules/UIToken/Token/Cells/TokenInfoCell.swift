import UIKit
import UIActivityList
import UIComponents

final class TokenInfoCell: FirstRowCell {
    private let card = TokenInfoCardView()

    override var height: CGFloat? {
        get { card.currentHeight }
        set { card.currentHeight = newValue ?? 0 }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        card.prepareForReuse()
    }

    func configure(
        model: TokenInfoModel,
        onHeightChange: @escaping () -> Void,
        onUserToggleAnimationChange: @escaping (Bool) -> Void
    ) {
        card.configure(model: model, onHeightChange: onHeightChange,
                       onUserToggleAnimationChange: onUserToggleAnimationChange)
    }

    func modelStateDidChange() {
        card.modelStateDidChange()
    }
}
