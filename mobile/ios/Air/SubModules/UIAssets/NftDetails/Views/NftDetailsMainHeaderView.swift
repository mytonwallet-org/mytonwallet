import UIKit

protocol NftDetailsMainHeaderViewDelegate: AnyObject {
    func headerCoverFlowDidSelectModel(_ model: NftDetailsItemModel)
    func headerCoverFlowDidScroll(withProgress progress: CGFloat, currentModelId: String)
    func headerCoverFlowDidTapModel(_ model: NftDetailsItemModel, view: UIView, longTap: Bool)
}

class NftDetailsMainHeaderView: UIView {
    private weak var delegate: NftDetailsMainHeaderViewDelegate?

    let collapsedHeight: CGFloat = 165
    private var fullCollapsedHeight: CGFloat { collapsedHeight + topSafeAreaInset }
    private var coverFlowTopConstraintValue: CGFloat { topSafeAreaInset }
    private var heightConstraint: NSLayoutConstraint!
    private var coverFlowTopConstraint: NSLayoutConstraint!

    var topSafeAreaInset: CGFloat = 0 {
        didSet {
            if topSafeAreaInset != oldValue {
                heightConstraint.constant = fullCollapsedHeight
                coverFlowTopConstraint.constant = coverFlowTopConstraintValue
            }
        }
    }

    private let coverFlowView: _CoverFlowView

    private let gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [
            UIColor.black.withAlphaComponent(0.3).cgColor,
            UIColor.black.withAlphaComponent(0.0).cgColor
        ]
        layer.locations = [0, 1]
        return layer
    }()

    init(models: [NftDetailsItemModel], delegate: NftDetailsMainHeaderViewDelegate) {
        self.delegate = delegate
        self.coverFlowView = _CoverFlowView(models: models)

        super.init(frame: .fromSize(width: 300, height: 600))

        self.coverFlowView.delegate = self
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        var b = bounds
        b.size.height += 60
        gradientLayer.frame = b
    }

    private func setup() {
        clipsToBounds = false
        layer.masksToBounds = false
        layer.addSublayer(gradientLayer)

        coverFlowView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverFlowView)

        heightConstraint = heightAnchor.constraint(equalToConstant: fullCollapsedHeight)
        coverFlowTopConstraint = coverFlowView.topAnchor.constraint(equalTo: topAnchor, constant: coverFlowTopConstraintValue)
        NSLayoutConstraint.activate([
            heightConstraint,
            coverFlowTopConstraint,
            coverFlowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverFlowView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    
    func selectedCoverFlowTileFrame() -> CGRect { coverFlowView.frameOfSelectedItem() }
        
    func setActive(_ isActive: Bool) {
        isUserInteractionEnabled = isActive
        UIView.animate(withDuration: 0.25) { [weak self] in
            self?.coverFlowView.isActive = isActive
            self?.gradientLayer.opacity = isActive ? 1 : 0
        }
    }
    
    func selectCoverFlowModel(_ model: NftDetailsItemModel, animated: Bool, forced: Bool) {
        coverFlowView.selectModel(byId: model.id, animated: animated, forced: forced)
    }
    
    func syncCoverFlowWithPager(progress: CGFloat, currentItemId: String) {
        coverFlowView.setCoverFlowProgress(currentItemId: currentItemId, progress: progress)
    }
}

extension NftDetailsMainHeaderView: CoverFlowDelegate {    
    func coverFlowDidTapModel(_ model: NftDetailsItemModel, view: UIView,  longTap: Bool) {
        delegate?.headerCoverFlowDidTapModel(model, view: view, longTap: longTap)
    }
        
    func coverFlowDidSelectModel(_ model: NftDetailsItemModel) {
        delegate?.headerCoverFlowDidSelectModel(model)
    }
    
    func onCoverFlowScrollProgress(_ progress: CGFloat, currentItemId: String) {
        delegate?.headerCoverFlowDidScroll(withProgress: progress, currentModelId: currentItemId)
    }
}
