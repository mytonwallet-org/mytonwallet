import UIKit
import UIComponents
import WalletCore
import WalletContext


public class AddViewWalletVC: CreateWalletBaseVC {

    private let introModel: IntroModel
    private let autofocusesOnAppear: Bool

    private var headerView: HeaderView!
    private var addressContainer: UIView!
    private var addressTextView: UITextView!
    private var placeholderLabel: UILabel!
    private var pasteButton: UIButton!
    private var clearButton: UIButton!
    private var continueButton: WButton!
    private var continueButtonKeyboardConstraint: NSLayoutConstraint!
    private var continueButtonHiddenConstraint: NSLayoutConstraint!
    private var continueButtonFrozenConstraint: NSLayoutConstraint?
    private var isSubmitting = false
    
    public init(introModel: IntroModel, autofocusesOnAppear: Bool = true) {
        self.introModel = introModel
        self.autofocusesOnAppear = autofocusesOnAppear
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    func setupViews() {
        addCloseNavigationItemIfNeeded()

        let isCompactScreen = screenHeight < 700

        headerView = HeaderView(
            animationName: "animation_bill",
            animationPlaybackMode: .loop,
            title: lang("View Mode"),
            description: lang("$import_view_account_note"),
            animationSize: isCompactScreen ? 120 : 160
        )
        view.addSubview(headerView)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        addressContainer = UIView()
        addressContainer.translatesAutoresizingMaskIntoConstraints = false
        addressContainer.backgroundColor = .air.sheetBackground
        addressContainer.layer.cornerRadius = S.insetSectionCornerRadius
        addressContainer.layer.masksToBounds = true
        view.addSubview(addressContainer)

        addressTextView = UITextView()
        addressTextView.translatesAutoresizingMaskIntoConstraints = false
        addressTextView.isScrollEnabled = false
        addressTextView.backgroundColor = .clear
        addressTextView.font = .systemFont(ofSize: 17)
        addressTextView.autocorrectionType = .no
        addressTextView.autocapitalizationType = .none
        addressTextView.keyboardType = .webSearch
        addressTextView.textContainerInset = .zero
        addressTextView.textContainer.lineBreakMode = .byCharWrapping
        addressTextView.textContainer.lineFragmentPadding = 0
        addressTextView.textContainer.maximumNumberOfLines = 0
        addressTextView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label,
        ]
        addressTextView.dataDetectorTypes = []
        addressTextView.returnKeyType = .continue
        if #available(iOS 18.0, *) {
            addressTextView.writingToolsBehavior = .none
        }
        addressTextView.delegate = self
        addressTextView.setContentCompressionResistancePriority(.required, for: .vertical)
        addressContainer.addSubview(addressTextView)

        placeholderLabel = UILabel()
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = lang("Wallet address or domain")
        placeholderLabel.font = .systemFont(ofSize: 17)
        placeholderLabel.textColor = UIColor.placeholderText
        addressContainer.addSubview(placeholderLabel)
        
        pasteButton = UIButton(type: .system)
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.setTitle(lang("Paste"), for: .normal)
        pasteButton.titleLabel?.font = .systemFont(ofSize: 17)
        pasteButton.tintColor = .tintColor
        pasteButton.addTarget(self, action: #selector(onPaste), for: .touchUpInside)
        addressContainer.addSubview(pasteButton)
        
        clearButton = UIButton(type: .system)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = .air.secondaryLabel
        clearButton.addTarget(self, action: #selector(onClear), for: .touchUpInside)
        clearButton.alpha = 0.8
        addressContainer.addSubview(clearButton)

        continueButton = addBottomButton(bottomConstraint: false)
        continueButton.setTitle(lang("Continue"), for: .normal)
        continueButton.addTarget(self, action: #selector(onContinue), for: .touchUpInside)
        continueButton.isEnabled = false

        let keyboardGuide = view.keyboardLayoutGuide
        continueButtonKeyboardConstraint = continueButton.bottomAnchor.constraint(equalTo: keyboardGuide.topAnchor, constant: -16)
        continueButtonHiddenConstraint = continueButton.topAnchor.constraint(equalTo: view.bottomAnchor, constant: 100)

        NSLayoutConstraint.activate([
            continueButtonHiddenConstraint,
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0).withPriority(.defaultLow),
            headerView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 8),
            headerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            headerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),

            addressContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: isCompactScreen ? 16 : 32),
            addressContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            addressContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            
            addressTextView.topAnchor.constraint(equalTo: addressContainer.topAnchor, constant: 16),
            addressTextView.bottomAnchor.constraint(equalTo: addressContainer.bottomAnchor, constant: -16),
            addressTextView.leadingAnchor.constraint(equalTo: addressContainer.leadingAnchor, constant: 16),
            addressTextView.trailingAnchor.constraint(lessThanOrEqualTo: pasteButton.leadingAnchor, constant: -12),
            addressTextView.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -8),

            placeholderLabel.leadingAnchor.constraint(equalTo: addressTextView.leadingAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: addressTextView.centerYAnchor),

            pasteButton.centerYAnchor.constraint(equalTo: addressTextView.centerYAnchor),
            pasteButton.trailingAnchor.constraint(equalTo: addressContainer.trailingAnchor, constant: -12),
            
            clearButton.centerYAnchor.constraint(equalTo: addressTextView.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: addressContainer.trailingAnchor, constant: -12),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalTo: clearButton.widthAnchor),
            
            continueButton.topAnchor.constraint(greaterThanOrEqualTo: addressContainer.bottomAnchor, constant: 16),
        ])

        updateActionsVisibility()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
        freezeContinueButtonPosition()
    }

    private func freezeContinueButtonPosition() {
        guard continueButtonKeyboardConstraint.isActive else { return }
        let frozenY = continueButton.frame.minY
        continueButtonKeyboardConstraint.isActive = false
        continueButtonFrozenConstraint?.isActive = false
        let frozenConstraint = continueButton.topAnchor.constraint(equalTo: view.topAnchor, constant: frozenY)
        continueButtonFrozenConstraint = frozenConstraint
        frozenConstraint.isActive = true
    }

    private func restoreContinueButtonKeyboardConstraintIfNeeded() {
        guard !continueButtonHiddenConstraint.isActive else { return }
        continueButtonFrozenConstraint?.isActive = false
        continueButtonFrozenConstraint = nil
        continueButtonKeyboardConstraint.isActive = true
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if autofocusesOnAppear {
            focusAddressField()
        }
        showContinueButtonIfNeeded()
    }

    private func showContinueButtonIfNeeded() {
        guard continueButtonHiddenConstraint.isActive else { return }
        continueButtonHiddenConstraint.isActive = false
        continueButtonFrozenConstraint?.isActive = false
        continueButtonFrozenConstraint = nil
        continueButtonKeyboardConstraint.isActive = true
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.view.layoutIfNeeded()
        }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        restoreContinueButtonKeyboardConstraintIfNeeded()
    }
    
    public func focusAddressField() {
        if addressTextView.text.isEmpty {
            addressTextView.becomeFirstResponder()
        }
    }
    
    private func getTrimmedInput() -> String {
        addressTextView?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private func updateActionsVisibility() {
        let trimmedValue = getTrimmedInput()
        let isEmpty = trimmedValue.isEmpty
        placeholderLabel.isHidden = !addressTextView.text.isEmpty
        pasteButton.isHidden = !isEmpty
        clearButton.isHidden = isEmpty
        continueButton.isEnabled = !isEmpty && !isSubmitting
    }
    
    @objc private func onContinue() {
        guard !isSubmitting else { return }
        let value = getTrimmedInput()
        guard !value.isEmpty else {
            updateActionsVisibility()
            return
        }
        isSubmitting = true
        continueButton.showLoading = true
        continueButton.isEnabled = false
        Task { @MainActor in
            do {
                try await introModel.onAddViewWalletContinue(address: value)
            } catch {
                AppActions.showError(error: error)
                isSubmitting = false
                continueButton.showLoading = false
                updateActionsVisibility()
            }
        }
    }
    
    @objc private func onPaste() {
        if let string = UIPasteboard.general.string?.nilIfEmpty {
            addressTextView.text = string
            updateActionsVisibility()
        }
    }
    
    @objc private func onClear() {
        addressTextView.text = ""
        updateActionsVisibility()
    }
}

extension AddViewWalletVC: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        updateActionsVisibility()
    }
    
    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            onContinue()
            return false
        }
        return true
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    let introModel = IntroModel(network: .mainnet, password: nil)
    AddViewWalletVC(introModel: introModel)
}
#endif
