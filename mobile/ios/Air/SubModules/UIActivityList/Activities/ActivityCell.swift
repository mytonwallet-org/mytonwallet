
import Kingfisher
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception
import Dependencies
import SwiftNavigation

@Perceptible @MainActor
public class ActivityCellViewModel {
    
    @PerceptionIgnored
    var activity: ApiActivity
    
    @PerceptionIgnored
    var tokenStore: _TokenStore
    @PerceptionIgnored
    @AccountContext var account: MAccount
    
    init(accountId: String?, activity: ApiActivity) {
        @Dependency(\.tokenStore) var tokenStore
        self.tokenStore = tokenStore
        self._account = AccountContext(accountId: accountId)
        self.activity = activity
    }
}

public class ActivityCell: WHighlightCollectionViewCell {

    @MainActor
    public protocol Delegate: AnyObject {
        func onSelect(transaction: ApiActivity)
    }
    
    class Layer: CALayer {
        override var cornerRadius: CGFloat {
            get { S.homeInsetSectionCornerRadius }
            set { _ = newValue }
        }
    }
    public override class var layerClass: AnyClass { Layer.self }

    static let regular14Font = UIFont.systemFont(ofSize: 14, weight: .regular)
    static let regular16Font = UIFont.systemFont(ofSize: 16, weight: .regular)
    static let medium16Font = UIFont.systemFont(ofSize: 16, weight: .medium)
    
    var skeletonView: ActivitySkeletonView? = nil

    let mainView = UIView()
    let firstTwoRows: UIView = .init()
    
    let iconView: IconView = .init(size: 40, accessoryGeometry: .forIcon40)
    
    let titleLabel: UILabel = .init()
    private let scamBadge: UIImageView = .init()
    
    let detailsLabel: UILabel = .init()
    
    private let rightChevron: UIImageView = {
        let imageView = UIImageView(image: .airBundle("RightArrowIcon"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    private let amountContainer: WSensitiveData<UILabel> = .init(cols: 12, rows: 2, cellSize: 9, cornerRadius: 5, theme: .adaptive, alignment: .trailing)
    private let amountLabel = WAmountLabel()
    private let amount2Container: WSensitiveData<UILabel> = .init(cols: 9, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .trailing)
    private let amount2Label = UILabel()
    private var amountIcons = AmountIcons()

    private(set) var nftView: NftPreviewLarge = .init()
    private var nftViewConstraints: [NSLayoutConstraint] = []
    
    var commentView: BubbleView = .init()
    private var commentViewConstraints: [NSLayoutConstraint] = []
    private var commentViewLeadingConstraint: NSLayoutConstraint!
    private var commentViewTrailingConstraint: NSLayoutConstraint!
    private var firstTwoRowsTrailingConstraint: NSLayoutConstraint!
    private var firstTwoRowsTrailingToChevronConstraint: NSLayoutConstraint!

    var nftAndCommentConstraint: NSLayoutConstraint!
    
    weak var delegate: Delegate? = nil
    var activity: ApiActivity?
    private var trackedValue: Double?

    private var viewModel: ActivityCellViewModel!
    
    private var observeAccountAndActivity: ObserveToken?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        contentView.alpha = 1
        setShowsRightChevron(false)
    }
    
    @objc private func itemSelected() {
        if let activity, let delegate {
            delegate.onSelect(transaction: activity)
        }
    }

    func setupViews() {
        isExclusiveTouch = true
        layer.cornerRadius = 20
        
        contentView.isUserInteractionEnabled = true
        contentView.backgroundColor = .clear
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemSelected)))
        // setup whole cell as a vertical stack view
        
        mainView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainView)
        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            mainView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            mainView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10).withPriority(.init(999)), // affordance for cell separator
        ])

        // MARK: left icon
        mainView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: mainView.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
        ])
        
        firstTwoRows.accessibilityIdentifier = "firstTwoRows"
        firstTwoRows.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(firstTwoRows)
        mainView.addSubview(rightChevron)
        rightChevron.isHidden = true
        
        firstTwoRowsTrailingConstraint = firstTwoRows.trailingAnchor.constraint(equalTo: mainView.trailingAnchor)
        firstTwoRowsTrailingToChevronConstraint = firstTwoRows.trailingAnchor.constraint(equalTo: rightChevron.leadingAnchor, constant: -10)
        firstTwoRowsTrailingToChevronConstraint.isActive = false
        NSLayoutConstraint.activate([
            firstTwoRows.topAnchor.constraint(equalTo: mainView.topAnchor),
            firstTwoRows.bottomAnchor.constraint(equalTo: mainView.bottomAnchor).withPriority(.init(500)),
            firstTwoRowsTrailingConstraint,
            firstTwoRows.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            
            rightChevron.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            rightChevron.centerYAnchor.constraint(equalTo: firstTwoRows.centerYAnchor),
        ])

        // MARK: address
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(titleLabel)
        titleLabel.font = ActivityCell.medium16Font
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: firstTwoRows.topAnchor, constant: 1.667),
            titleLabel.leadingAnchor.constraint(equalTo: firstTwoRows.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: firstTwoRows.trailingAnchor)
        ])
        
        scamBadge.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(scamBadge)
        scamBadge.contentMode = .center
        NSLayoutConstraint.activate([
            scamBadge.bottomAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor, constant: 2),
            scamBadge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4.333),
        ])
        scamBadge.isHidden = true
        
        // MARK: type + time
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(detailsLabel)
        NSLayoutConstraint.activate([
            detailsLabel.heightAnchor.constraint(equalToConstant: 18),
            detailsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1)
        ])
        detailsLabel.font = ActivityCell.regular14Font
        detailsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailsLabel.lineBreakMode = .byTruncatingMiddle
        
        // MARK: amount1
        amountLabel.font = Self.regular16Font
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountContainer.addContent(amountLabel)
        firstTwoRows.addSubview(amountContainer)
        NSLayoutConstraint.activate([
            amountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            amountLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
        ])
        
        // MARK: amount2
        amount2Label.font = Self.regular14Font
        amount2Label.textColor = .air.secondaryLabel
        amount2Label.translatesAutoresizingMaskIntoConstraints = false
        amount2Label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        amount2Container.addContent(amount2Label)
        firstTwoRows.addSubview(amount2Container)
        NSLayoutConstraint.activate([
            amount2Label.firstBaselineAnchor.constraint(equalTo: detailsLabel.firstBaselineAnchor),
            amount2Label.leadingAnchor.constraint(greaterThanOrEqualTo: detailsLabel.trailingAnchor, constant: 6)
        ])

        NSLayoutConstraint.activate([
            firstTwoRows.heightAnchor.constraint(equalToConstant: 40)
        ])

        amountIcons.translatesAutoresizingMaskIntoConstraints = false
        firstTwoRows.addSubview(amountIcons)

        let amountLabelTrailingConstraint = amountLabel.trailingAnchor.constraint(equalTo: firstTwoRows.trailingAnchor)
        let amount2LabelTrailingConstraint = amount2Label.trailingAnchor.constraint(equalTo: firstTwoRows.trailingAnchor)
        NSLayoutConstraint.activate([
            amountLabelTrailingConstraint,
            amount2LabelTrailingConstraint,
            amountIcons.topAnchor.constraint(equalTo: firstTwoRows.topAnchor),
            amountIcons.bottomAnchor.constraint(equalTo: firstTwoRows.bottomAnchor),
            amountIcons.trailingAnchor.constraint(equalTo: firstTwoRows.trailingAnchor)
        ])
        amountIcons.attachTo(
            amountLabelTrailingConstraint: amountLabelTrailingConstraint,
            amountLabelBaselineAnchor: amountLabel.firstBaselineAnchor,
            amount2LabelTrailingConstraint: amount2LabelTrailingConstraint
        )
        
        amountContainer.isTapToRevealEnabled = false
        amount2Container.isTapToRevealEnabled = false
        
        // MARK: Nft
        
        nftView.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(nftView)
        nftViewConstraints = [
            nftView.topAnchor.constraint(equalTo: firstTwoRows.bottomAnchor, constant: 6),
            nftView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor).withPriority(.init(510)),
            nftView.leadingAnchor.constraint(equalTo: firstTwoRows.leadingAnchor),
            nftView.trailingAnchor.constraint(lessThanOrEqualTo: mainView.trailingAnchor),
        ]
        
        // MARK: Comment
        
        commentView.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(commentView)
        commentViewConstraints = [
            commentView.topAnchor.constraint(equalTo: firstTwoRows.bottomAnchor, constant: 6).withPriority(.init(910)),
            commentView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            
            commentView.leadingAnchor.constraint(greaterThanOrEqualTo: firstTwoRows.leadingAnchor),
            commentView.trailingAnchor.constraint(lessThanOrEqualTo: mainView.trailingAnchor),
        ]
        commentViewLeadingConstraint = commentView.leadingAnchor.constraint(equalTo: firstTwoRows.leadingAnchor)
        commentViewTrailingConstraint = commentView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor)
        
        // MARK: Shared constraints
        nftAndCommentConstraint = commentView.topAnchor.constraint(equalTo: nftView.bottomAnchor, constant: 6).withPriority(.init(920))
        
        updateTheme()
    }

    private func updateTheme() {
        baseBackgroundColor = UIColor.air.groupedItem
        contentView.backgroundColor = .clear
        highlightBackgroundColor = UIColor.air.highlight
        skeletonView?.backgroundColor = UIColor.air.groupedItem
        detailsLabel.textColor = UIColor.air.secondaryLabel
        amount2Label.textColor = UIColor.air.secondaryLabel
    }
    
    private func setShowsRightChevron(_ shows: Bool) {
        rightChevron.isHidden = !shows
        firstTwoRowsTrailingConstraint.isActive = !shows
        firstTwoRowsTrailingToChevronConstraint.isActive = shows
    }

    
    // MARK: - Configure
    
    public func configure(with activity: ApiActivity, accountContext: AccountContext, delegate: Delegate, showsRightChevron: Bool = false) {
        if skeletonView?.alpha ?? 0 > 0 {
            skeletonView?.alpha = 0
            mainView.alpha = 1
        }
        self.activity = activity
        self.delegate = delegate
        setShowsRightChevron(showsRightChevron)

        self.configureViewModel(accountId: accountContext.accountId, activity: activity)
        
        iconView.config(with: activity)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        configureTitle(activity: activity)
        configureDetails(.init(activity: activity, accountContext: accountContext, isEmulation: false))
        configureAmount(.init(activity: activity, tokenStore: viewModel.tokenStore))
        configureAmount2(.init(activity: activity, tokenStore: viewModel.tokenStore))
        configureSensitiveData(activity: activity)
        configureNft(activity: activity)
        configureComment(activity: activity)
        
        nftAndCommentConstraint.isActive = !nftView.isHidden && !commentView.isHidden
        
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
        }
        
        CATransaction.commit()
    }
    
    private func configureViewModel(accountId: String, activity: ApiActivity) {
        if viewModel == nil {
            viewModel = ActivityCellViewModel(accountId: accountId, activity: activity)
            observeAccountAndActivity = observe { [weak self] in
                guard let self else { return }
                let activity = viewModel.activity
                if let chain = getChainBySlug(activity.slug), let peerAddress = activity.peerAddress {
                    _ = viewModel.$account.getLocalName(chain: chain, address: peerAddress)
                }
                configureDetails(.init(activity: activity, accountContext: viewModel.$account, isEmulation: false))
                configureAmount(.init(activity: activity, tokenStore: viewModel.tokenStore))
                configureAmount2(.init(activity: activity, tokenStore: viewModel.tokenStore))
            }
        } else {
            viewModel.$account.accountId = accountId
            viewModel.activity = activity
        }
    }
    
    public func updateToken() {
        if let activity {
            if amountIcons.hasUnloadedIcons {
                configureAmount(.init(activity: activity, tokenStore: viewModel.tokenStore))
            }
            if !amount2Label.isHidden, case .transaction(let tx) = activity, let token = viewModel.tokenStore[tx.slug], token.price != self.trackedValue {
                configureAmount2(.init(activity: activity, tokenStore: viewModel.tokenStore))
            }
        }
    }
    
    func configureTitle(activity: ApiActivity, isEmulation: Bool = false) {
        if isEmulation {
            titleLabel.text = activity.displayTitle.future
        } else {
            titleLabel.text = activity.displayTitleResolvedOptimistic
        }
        
        if activity.isScamTransaction {
            if scamBadge.image == nil {
                scamBadge.image = .airBundle("ScamBadge")
            }
            scamBadge.isHidden = false
        } else {
            scamBadge.isHidden = true
        }
    }
    
    @MainActor struct ConfigureDetailsOptions {
        var activity: ApiActivity
        var isMultichain = false
        var stakingState: ApiStakingState?
        var accountChains: Set<ApiChain> = []
        var isEmulation: Bool
        var address: String = ""
        var addressLabelKey: String = "$transaction_to"
        
        init(activity: ApiActivity, accountContext: AccountContext, isEmulation: Bool) {
            self.activity = activity
            self.isEmulation = isEmulation
            self.accountChains = accountContext.account.supportedChains
            if  case .transaction(let transaction) = activity {
                isMultichain = accountContext.account.isMultichain
                if activity.shouldShowTransactionAnnualYield {
                    stakingState = accountContext.stakingData?.bySlug(activity.slug)
                }
                if let address = transaction.extra?.dex?.displayName ?? transaction.extra?.marketplace?.displayName {
                    self.address = address
                    self.addressLabelKey = "$transaction_on"
                } else {
                    self.addressLabelKey = transaction.isIncoming ? "$transaction_from" : "$transaction_to"
                    let chain = getChainBySlug(transaction.slug) ?? FALLBACK_CHAIN
                    let vm = AddressViewModel.fromTransaction(transaction, chain: chain, addressKind: .peer).withLocalName(account: accountContext)
                    if let name = vm.name {
                        self.address = name
                    } else {
                        self.address = formatStartEndAddress(vm.address ?? "", prefix: 4, suffix: 4)
                    }
                }
            }
        }
    }
            
    func configureDetails(_ options: ConfigureDetailsOptions) {
        let activity = options.activity
        let attr = NSMutableAttributedString()
        let detailsAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.regular14Font
        ]
        
        switch activity {
        case .transaction(let transaction):
            if transaction.status == .failed {
                attr.append(NSAttributedString(string: lang("Failed"), attributes: detailsAttributes))
            }
            
            if activity.shouldShowTransactionAddress(in: .list) {
                if !attr.string.isEmpty {
                    attr.append(NSAttributedString(string: " · ", attributes: detailsAttributes))
                }
                
                let addressFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
                var address = NSAttributedString(string: options.address, attributes: [
                    .font: addressFont
                ])
                
                if let chain = getChainBySlug(activity.slug) {
                    address = ChainIcon(chain).prepended(to: options.address, font: addressFont, separator: .hairline)
                }
                
                attr.append(attributedLang(
                    options.addressLabelKey,
                    attributes: detailsAttributes,
                    arg1: address
                ))
                
            }
            
            if activity.shouldShowTransactionAnnualYield, let stakingState = options.stakingState {
                if !attr.string.isEmpty {
                    attr.append(NSAttributedString(string: " · ", attributes: detailsAttributes))
                }
                let annualYield = NSAttributedString(string: "\(stakingState.yieldType.rawValue) \(stakingState.annualYield.value)%", attributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
                ])
                attr.append(attributedLang(
                    "at %annual_yield%",
                    attributes: detailsAttributes,
                    arg1: annualYield
                ))
            } else {
                // TODO: auction bid, nft bought
            }
        case .swap(let swap):
            var status: String?
            switch swap.displayStatus(accountChains: options.accountChains) {
            case .waitingForPayment:
                status = lang("Waiting for Payment")
            case .pending:
                status = lang("In Progress")
            case .hold:
                status = lang("On Hold")
            case .expired:
                status = lang("Expired")
            case .refunded:
                status = lang("Refunded")
            case .failed:
                status = lang("Failed")
            case .completed:
                status = nil
            }
            if let status {
                attr.append(NSAttributedString(string: status, attributes: detailsAttributes))
            }
        }
        if !options.isEmulation {
            if !attr.string.isEmpty {
                attr.append(NSAttributedString(string: " · ", attributes: detailsAttributes))
            }
            let timestamp = stringForTimestamp(timestamp: Int32(clamping: activity.timestamp / 1000))
            attr.append(NSAttributedString(string: timestamp, attributes: detailsAttributes))
        }
        detailsLabel.textColor = UIColor.air.secondaryLabel
        detailsLabel.attributedText = attr
    }
    
    struct ConfigureAmountOptions {
        var activity: ApiActivity
        var transactionToken: ApiToken?
        var baseCurrency: MBaseCurrency
        
        init(activity: ApiActivity, tokenStore: _TokenStore) {
            if case .transaction(let transaction) = activity {
                transactionToken = tokenStore[transaction.slug]
            }
            self.baseCurrency = tokenStore.baseCurrency
            self.activity = activity
        }
    }
        
    func configureAmount(_ options: ConfigureAmountOptions) {
        let activity = options.activity
        let displayMode = activity.amountDisplayMode

        switch activity {
        case .transaction(let transaction):
            if displayMode != .hide, let token = options.transactionToken {
                let amount = TokenAmount(transaction.amount, token)
                let color: UIColor = transaction.type == .stake ? .air.textPurple : transaction.isIncoming ? UIColor.air.positiveAmount : UIColor.label
                let amountString = amount.formatAttributed(
                    format: .init(
                        preset: .defaultAdaptive,
                        showPlus: displayMode == .noSign ? false : true,
                        showMinus: displayMode == .noSign ? false : true,
                        roundHalfUp: false
                    ),
                    integerFont: UIFont.systemFont(ofSize: 16),
                    fractionFont: UIFont.systemFont(ofSize: 16),
                    symbolFont: UIFont.systemFont(ofSize: 16),
                    integerColor: color,
                    fractionColor: color,
                    symbolColor: color
                )
                amountLabel.attributedText = amountString
                if displayMode == .hide {
                    amountIcons.setHideMode()
                } else {
                    amountIcons.setTransactionMode(token: token)
                }
            } else {
                amountLabel.text = nil
                amountIcons.setHideMode()
            }
            
        case .swap(let swap):
            if let fromToken = swap.fromToken, let toToken = swap.toToken {
                let fromDecimalAmount = DecimalAmount.fromDouble(-swap.fromAmount.value, fromToken)
                let from = fromDecimalAmount.formatted(.compact, showMinus: true)
                amountLabel.attributedText = swapAmountText(text: from, swap: swap, isFrom: true)
                amountIcons.setSwapMode(fromToken: fromToken, toToken: toToken)
            } else {
                amountLabel.attributedText = nil
                amountIcons.setHideMode()
            }
        }
        
        amountLabel.isHidden = displayMode == .hide
    }
    
    private func swapAmountText(text: String, swap: ApiSwapActivity, isFrom: Bool) -> NSAttributedString {
        var color: UIColor
        if swap.cex?.status == .hold {
            color = .air.secondaryLabel
        } else {
            switch swap.status {
            case .expired, .failed:
                color = .air.error
            case .pending, .pendingTrusted, .confirmed, .completed:
                color = isFrom ? .air.secondaryLabel : .air.positiveAmount
            }
        }
        
        return NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: isFrom ? Self.regular14Font : Self.regular16Font
        ])
    }
        
    func configureAmount2(_ options: ConfigureAmountOptions) {
        let activity = options.activity
        
        amount2Label.font = .systemFont(ofSize: 14)
        amount2Label.textColor = UIColor.air.secondaryLabel
        
        let displayMode = activity.amountDisplayMode
        amount2Label.isHidden = displayMode == .hide
        
        switch activity {
        case .transaction(let transaction):
            if displayMode != .hide, let token = options.transactionToken, let price = token.price {
                let amount: BaseCurrencyAmount = TokenAmount(transaction.amount, token).convertTo(options.baseCurrency, exchangeRate: price)
                let color = UIColor.air.secondaryLabel
                let amountString = amount.formatAttributed(
                    format: .init(
                        preset: .baseCurrencyEquivalent,
                        showMinus: false,
                        roundHalfUp: false
                    ),
                    integerFont: UIFont.systemFont(ofSize: 14),
                    fractionFont: UIFont.systemFont(ofSize: 14),
                    symbolFont: UIFont.systemFont(ofSize: 14),
                    integerColor: color,
                    fractionColor: color,
                    symbolColor: color
                )
                amount2Label.attributedText = amountString
                self.trackedValue = token.price
            } else {
                amount2Label.text = nil
                self.trackedValue = nil
            }
        case .swap(let swap):
            if let toToken = swap.toToken {
                let toDecimalAmount = DecimalAmount.fromDouble(swap.toAmount.value, toToken)
                let to = toDecimalAmount.formatted(.compact, showPlus: true, showMinus: false)
                amount2Label.attributedText = swapAmountText(text: to, swap: swap, isFrom: false)
            } else {
                amount2Label.attributedText = nil
            }
            self.trackedValue = nil
        }
    }
    
    
    func configureSensitiveData(activity: ApiActivity?) {
        if let activity, activity.amountDisplayMode != .hide {
            let amountCols = 4 + abs(activity.id.hash % 8)
            let fiatAmountCols = 5 + (amountCols % 6)
            amountContainer.setCols(amountCols)
            amount2Container.setCols(fiatAmountCols)
            if let tx = activity.transaction, tx.isIncoming, tx.amount > 0, tx.nft == nil {
                amountContainer.setTheme(.color(UIColor.air.positiveAmount))
            } else {
                amountContainer.setTheme(.adaptive)
            }
            amountContainer.isDisabled = false
            amount2Container.isDisabled = false
        } else {
            amountContainer.isDisabled = true
            amount2Container.isDisabled = true
        }
    }
    
    func configureNft(activity: ApiActivity?) {
        
        if activity?.isScamTransaction != true, let nft = activity?.transaction?.nft {
            nftView.setNft(nft)
            nftView.isHidden = false
            NSLayoutConstraint.activate(nftViewConstraints)
        } else {
            nftView.isHidden = true
            NSLayoutConstraint.deactivate(nftViewConstraints)
        }
    }
    
    func configureComment(activity: ApiActivity?) {
        
        let hasComment: Bool
        let shouldShowComment = activity?.shouldShowTransactionComment == true
        let isIncoming = activity?.transaction?.isIncoming == true
        
        if shouldShowComment, let tx = activity?.transaction, let commment = tx.comment?.nilIfEmpty {
            commentView.setComment(commment, direction: isIncoming ? .incoming : .outgoing, isError: tx.status == .failed)
            hasComment = true
        } else if shouldShowComment, let tx = activity?.transaction, tx.encryptedComment != nil {
            commentView.setEncryptedComment(direction: isIncoming ? .incoming : .outgoing, isError: tx.status == .failed)
            hasComment = true
        } else {
            hasComment = false
        }
        
        commentView.isHidden = !hasComment
        if hasComment {
            NSLayoutConstraint.activate(commentViewConstraints)
            commentViewLeadingConstraint.isActive = isIncoming
            commentViewTrailingConstraint.isActive = !isIncoming
        } else {
            NSLayoutConstraint.deactivate(commentViewConstraints)
        }
    }
}

private class AmountIcons: UIView {
    private var amountLabelTrailingConstraint: NSLayoutConstraint!
    private var amount2LabelTrailingConstraint: NSLayoutConstraint!
    private var icon1BaselineConstraint: NSLayoutConstraint!
    private var icon1CenterYConstraint: NSLayoutConstraint!
    private var icon2CenterYConstraint: NSLayoutConstraint!

    private static let iconSize: CGFloat = 18
    private static let centerVOffset: CGFloat = 3
    private static let iconedLabelTrailingOffset: CGFloat = iconSize + 4

    private let icon1: IconView
    private var icon2: IconView?

    enum Mode {
        case hide
        case transaction
        case swap
    }
    
    private(set) var mode: Mode = .hide
    
    private lazy var icon1MaskLayer: CALayer = {
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        
        let b = CGRect.square(Self.iconSize)
        let outerPath = UIBezierPath(ovalIn: b)
        let oval = CGRect(origin: .init(x: 0, y: Self.iconSize - Self.centerVOffset * 2), size: b.size).insetBy(dx: -1, dy: -1)
        outerPath.append(UIBezierPath(ovalIn: oval))
        mask.path = outerPath.cgPath
        mask.frame = b
        return mask
    }()
    
    override init(frame: CGRect) {
        icon1 = IconView(size: Self.iconSize)
        
        super.init(frame: .zero)
        
        icon1.isHidden = true
        icon1.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon1)
                
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.iconSize),
            icon1.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func attachTo(
        amountLabelTrailingConstraint: NSLayoutConstraint,
        amountLabelBaselineAnchor: NSLayoutYAxisAnchor,
        amount2LabelTrailingConstraint: NSLayoutConstraint
    ) {
        self.amountLabelTrailingConstraint = amountLabelTrailingConstraint
        self.amount2LabelTrailingConstraint = amount2LabelTrailingConstraint

        icon1BaselineConstraint = icon1.bottomAnchor.constraint(equalTo: amountLabelBaselineAnchor, constant: 3)
        icon1CenterYConstraint = icon1.bottomAnchor.constraint(equalTo: centerYAnchor, constant: Self.centerVOffset)
    }
    
    var hasUnloadedIcons: Bool {
        switch mode {
        case .hide: false
        case .transaction: icon1.imageView.image == nil
        case .swap: icon1.imageView.image == nil || icon2?.imageView.image == nil
        }
    }
    
    func setHideMode() {
        mode = .hide
        icon1.isHidden = true
        icon2?.isHidden = true
        amountLabelTrailingConstraint.constant = 0
        amount2LabelTrailingConstraint.constant = 0
    }
    
    private func setIcon1Mask(_ maskLayer: CALayer?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        icon1.layer.mask = maskLayer
        CATransaction.commit()
    }
    
    func setSwapMode(fromToken: ApiToken, toToken: ApiToken) {
        mode = .swap
        icon1.config(with: fromToken, shouldShowChain: false)
        icon1.isHidden = false
        icon1BaselineConstraint.isActive = false
        icon1CenterYConstraint.isActive = true
        amountLabelTrailingConstraint.constant = -Self.iconedLabelTrailingOffset
        setIcon1Mask(icon1MaskLayer)

        if icon2 == nil {
            let icon2 = IconView(size: Self.iconSize)
            self.icon2 = icon2
            icon2.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon2)
            
            icon2CenterYConstraint = icon2.topAnchor.constraint(equalTo: centerYAnchor, constant: -Self.centerVOffset)
            NSLayoutConstraint.activate([
                icon2.centerXAnchor.constraint(equalTo: centerXAnchor),
                icon2CenterYConstraint,
            ])
        }
        icon2?.config(with: toToken, shouldShowChain: false)
        icon2?.isHidden = false
        amount2LabelTrailingConstraint.constant = -Self.iconedLabelTrailingOffset
    }
    
    func setTransactionMode(token: ApiToken) {
        mode = .transaction
        icon1.config(with: token, shouldShowChain: false)
        icon1.isHidden = false
        icon1CenterYConstraint.isActive = false
        icon1BaselineConstraint.isActive = true
        amountLabelTrailingConstraint.constant = -Self.iconedLabelTrailingOffset
        setIcon1Mask(nil)

        icon2?.isHidden = true
        amount2LabelTrailingConstraint.constant = 0
    }
}
