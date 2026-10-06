//
//  ImportWalletVC.swift
//  UICreateWallet
//
//  Created by Sina on 4/21/23.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

private enum SecretWordsMode: Equatable {
    case words12
    case words24

    var wordCount: Int {
        switch self {
        case .words12:
            12
        case .words24:
            24
        }
    }

    var segmentIndex: Int {
        switch self {
        case .words12:
            0
        case .words24:
            1
        }
    }

    init?(wordCount: Int) {
        switch wordCount {
        case 12:
            self = .words12
        case 24:
            self = .words24
        default:
            return nil
        }
    }

    init?(segmentIndex: Int) {
        switch segmentIndex {
        case 0:
            self = .words12
        case 1:
            self = .words24
        default:
            return nil
        }
    }
}

public class ImportWalletVC: CreateWalletBaseVC {
    private let introModel: IntroModel
    private let scrollView = UIScrollView()
    private var wordInputs: [WWordInput] = []
    private let suggestionsView = WSuggestionsView()
    private let wordsStackView1 = UIStackView()
    private let wordsStackView2 = UIStackView()
    private var secretWordsMode = SecretWordsMode.words12
    private var isSubmitting = false
    
    private let bottomEdgeEffect = EdgeEffectView()
    private var navigationBackground: UIView?
    private var bottomActionLeading: NSLayoutConstraint!
    private var bottomActionTrailing: NSLayoutConstraint!
    private var bottomActionBottom: NSLayoutConstraint!
    private var hasBegunEditing = false
    private var isInitialFocusScrollPending = false
    private var isUpdatingWordsMode = false

    private lazy var wordsModeSegmentedControl: SecretWordsModeControl = {
        let control = SecretWordsModeControl()
        control.addTarget(self, action: #selector(wordsModeChanged), for: .valueChanged)
        return control
    }()
    private lazy var wordsModeHitArea = StickyControlHitArea(target: wordsModeSegmentedControl)

    private lazy var headerView = HeaderView(
        animationName: "animation_snitch",
        animationPlaybackMode: .once,
        title: lang("Enter Secret Words"),
        description: L10n.authImportMnemonicDescription(counts: langJoin([localizedIntegerString(12), localizedIntegerString(24)], .or)),
        animationSize: 96,
        descriptionSpacing: 20,
    )
    private lazy var bottomActionsView = BottomActionsView(
        primaryAction: BottomAction(
            title: lang("Continue"),
            onPress: { [weak self] in
                self?.continuePressed()
            }
        ),
        reserveSecondaryActionHeight: false
    )

    public init(introModel: IntroModel) {
        self.introModel = introModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard let parent, !(parent is UINavigationController) else { return }
        // Sheet replacement does not forward appearance callbacks to the new child.
        loadViewIfNeeded()
        parent.navigationItem.titleView = wordsModeHitArea
        parent.navigationItem.standardAppearance = navigationItem.standardAppearance
        parent.navigationItem.scrollEdgeAppearance = navigationItem.scrollEdgeAppearance
        parent.navigationItem.compactAppearance = navigationItem.compactAppearance
        parent.navigationItem.compactScrollEdgeAppearance = navigationItem.compactScrollEdgeAppearance
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isLoading {
            isSubmitting = false
            textChanged()
        }
    }

    private func setupViews() {
        view.backgroundColor = .air.groupedBackground
        navigationItem.title = nil
        if AccountStore.accountsById.count > 0 {
            addCloseNavigationItemIfNeeded()
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        // The Add Wallet sheet embeds this controller, so automatic inset
        // adjustment does not include its navigation bar consistently.
        scrollView.contentInsetAdjustmentBehavior = .never

        scrollView.keyboardDismissMode = .interactive
        if #available(iOS 26, *) {
            scrollView.topEdgeEffect.isHidden = true
            scrollView.bottomEdgeEffect.isHidden = true
        }

        // add scrollView to view controller's main view
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            // scrollView
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            // contentLayout
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        headerView.isUserInteractionEnabled = true
        headerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))

        scrollView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: -16),
            headerView.leadingAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            headerView.trailingAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])

        var pasteConfiguration = UIButton.Configuration.plain()
        pasteConfiguration.title = lang("Paste from Clipboard")
        pasteConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = WTypography.uiFont(.button)
            return attributes
        }
        let pasteButton = UIButton(configuration: pasteConfiguration)
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.addTarget(self, action: #selector(pasteFromClipboard), for: .touchUpInside)
        scrollView.addSubview(pasteButton)
        NSLayoutConstraint.activate([
            pasteButton.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            pasteButton.leadingAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            pasteButton.trailingAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            pasteButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        wordsStackView1.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView1.axis = .vertical
        wordsStackView1.spacing = 16
        wordsStackView1.semanticContentAttribute = .forceLeftToRight
        
        wordsStackView2.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView2.axis = .vertical
        wordsStackView2.spacing = 16
        wordsStackView2.semanticContentAttribute = .forceLeftToRight
        
        wordsModeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(wordsModeSegmentedControl)
        scrollView.addSubview(wordsStackView1)
        scrollView.addSubview(wordsStackView2)
        NSLayoutConstraint.activate([
            wordsModeSegmentedControl.topAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 16),
            wordsModeSegmentedControl.centerXAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerXAnchor),
            wordsModeSegmentedControl.heightAnchor.constraint(equalToConstant: 40),

            wordsStackView1.topAnchor.constraint(equalTo: wordsModeSegmentedControl.bottomAnchor, constant: 24),
            wordsStackView2.topAnchor.constraint(equalTo: wordsStackView1.topAnchor),
            
            wordsStackView1.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 32),
            wordsStackView2.leftAnchor.constraint(equalTo: wordsStackView1.rightAnchor, constant: 16),
            wordsStackView2.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -32),
            wordsStackView1.widthAnchor.constraint(equalTo: wordsStackView2.widthAnchor),
            wordsStackView2.bottomAnchor.constraint(equalTo: wordsStackView1.bottomAnchor),
        ])
        
        let fieldsCount = 24
        var previousWorkInput: WWordInput?
        for i in 0 ..< fieldsCount {
            let wordInput = WWordInput(wordNumber: i + 1, suggestionsView: suggestionsView, delegate: self)
            
            if let previousWorkInput {
                previousWorkInput.nextInput = wordInput
            }
            wordInputs.append(wordInput)
            previousWorkInput = wordInput
        }
        updateWordInputsLayout()
        
        wordsStackView1.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor).isActive = true

        navigationBackground = addCustomNavigationBarBackground(color: .air.groupedBackground, inside: scrollView)
        navigationBackground?.alpha = 0
        scrollView.bringSubviewToFront(wordsModeSegmentedControl)
        navigationItem.titleView = wordsModeHitArea

        bottomEdgeEffect.translatesAutoresizingMaskIntoConstraints = false
        bottomEdgeEffect.update(content: .air.groupedBackground, blur: true, alpha: 0.85, edge: .bottom, edgeSize: 48)
        view.addSubview(bottomEdgeEffect)
        view.addSubview(bottomActionsView)
        bottomActionLeading = bottomActionsView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 36)
        bottomActionTrailing = bottomActionsView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -36)
        bottomActionBottom = bottomActionsView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -2)
        NSLayoutConstraint.activate([
            bottomActionLeading,
            bottomActionTrailing,
            bottomActionBottom,
            bottomEdgeEffect.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomEdgeEffect.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomEdgeEffect.topAnchor.constraint(equalTo: bottomActionsView.topAnchor, constant: -16),
            bottomEdgeEffect.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.addSubview(suggestionsView)

        textChanged()

        WKeyboardObserver.observeKeyboard(delegate: self)
    }

    private func setWordsMode(_ mode: SecretWordsMode) {
        wordsModeSegmentedControl.selectedSegmentIndex = mode.segmentIndex
        guard secretWordsMode != mode else { return }

        let contentOffset = scrollView.contentOffset
        isUpdatingWordsMode = true
        isInitialFocusScrollPending = false
        secretWordsMode = mode
        UIView.performWithoutAnimation {
            updateWordInputsLayout()
            view.layoutIfNeeded()
            scrollView.setContentOffset(clampedContentOffset(contentOffset), animated: false)
        }
        isUpdatingWordsMode = false
        updateFloatingControls()
        textChanged()
    }

    private func updateWordInputsLayout() {
        let focusedInput = wordInputs.first { $0.textField.isFirstResponder }
        let activeWordCount = secretWordsMode.wordCount
        let columnWordCount = activeWordCount / 2

        for (index, wordInput) in wordInputs.enumerated() {
            let isActive = index < activeWordCount
            wordInput.isHidden = !isActive
            wordInput.previousInput = nil
            wordInput.nextInput = nil
            wordInput.advancesOnSuggestionSelection = false
            wordInput.textField.returnKeyType = index == activeWordCount - 1 ? .done : .next
        }

        for index in 0 ..< activeWordCount {
            let wordInput = wordInputs[index]
            wordInput.isHidden = false
            wordInput.previousInput = index > 0 ? wordInputs[index - 1] : nil
            wordInput.nextInput = index + 1 < activeWordCount ? wordInputs[index + 1] : nil
            wordInput.advancesOnSuggestionSelection = index + 1 < activeWordCount
        }

        let columns = [Array(wordInputs.prefix(columnWordCount)), Array(wordInputs[columnWordCount ..< activeWordCount])]
        for (stackView, inputs) in zip([wordsStackView1, wordsStackView2], columns) {
            for view in stackView.arrangedSubviews where !inputs.contains(where: { $0 === view }) {
                stackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
        for (stackView, inputs) in zip([wordsStackView1, wordsStackView2], columns) {
            for (index, input) in inputs.enumerated() where input.superview !== stackView {
                stackView.insertArrangedSubview(input, at: index)
            }
        }

        if let focusedInput {
            if focusedInput.wordNumber <= activeWordCount, !focusedInput.textField.isFirstResponder {
                focusedInput.textField.becomeFirstResponder()
            } else if focusedInput.wordNumber > activeWordCount {
                focusPreferredActiveInput()
            }
        }
    }

    private func focusPreferredActiveInput() {
        let activeInputs = wordInputs.prefix(secretWordsMode.wordCount)
        let targetInput = activeInputs.first { $0.trimmedText == nil } ?? activeInputs.last
        targetInput?.textField.becomeFirstResponder()
    }

    @objc private func wordsModeChanged(_ sender: SecretWordsModeControl) {
        guard let mode = SecretWordsMode(segmentIndex: sender.selectedSegmentIndex) else { return }
        setWordsMode(mode)
    }
    
    private func pasteWords(_ words: [String], startingInput input: WWordInput, clearsExistingWords: Bool = false) -> Bool {
        guard !words.isEmpty else { return false }

        let fullPhraseMode = fullPhraseMode(for: words, startingInput: input, clearsExistingWords: clearsExistingWords)
        let pasteStartInput: WWordInput
        if let fullPhraseMode, let firstInput = wordInputs.first {
            setWordsMode(fullPhraseMode)
            clearWordInputs()
            pasteStartInput = firstInput
        } else {
            if clearsExistingWords {
                clearWordInputs()
            }
            if words.count > SecretWordsMode.words12.wordCount {
                setWordsMode(.words24)
            }
            pasteStartInput = input
        }
        
        var input = pasteStartInput
        var lastInput = pasteStartInput
        for word in words {
            input.setText(word, notifyDelegate: false, goToNextInput: false)
            lastInput = input
            guard let i = input.nextInput else { break }
            input = i
        }

        textChanged()

        scrollToInput(lastInput, alignFirstRow: false)
        
        if enteredWords() != nil {
            continuePressedAsync()
            return true
        }
        return false
    }

    private func fullPhraseMode(for words: [String], startingInput input: WWordInput, clearsExistingWords: Bool) -> SecretWordsMode? {
        guard let mode = SecretWordsMode(wordCount: words.count) else { return nil }
        if mode == .words12,
           secretWordsMode == .words24,
           input.wordNumber == 13,
           !clearsExistingWords,
           wordInputs.prefix(12).allSatisfy({ $0.trimmedText != nil }) {
            return nil
        }
        return mode
    }

    private func clearWordInputs() {
        for input in wordInputs {
            input.setText("", notifyDelegate: false, goToNextInput: false)
        }
    }

    private func splitMnemonicWords(_ value: String) -> [String] {
        value.split { $0 == "," || $0.isWhitespace }.map(String.init)
    }

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc func pasteFromClipboard() {
        guard let firstInput = wordInputs.first else { return }
        
        if UIPasteboard.general.hasStrings, let value = UIPasteboard.general.string, !value.isEmpty {
            let words = splitMnemonicWords(value)
            
            if !pasteWords(words, startingInput: firstInput, clearsExistingWords: true) {
                view.endEditing(true)
                Haptics.play(.error)
            }
        } else {
            Haptics.play(.lightTap)
            AppActions.showToast(message: lang("Clipboard empty"))
        }
    }
    
    private func continuePressedAsync() {
        DispatchQueue.main.async { [weak self] in
            self?.continuePressed()
        }
    }

    private func continuePressed() {
        guard !isSubmitting, !isLoading else { return }
        
        isSubmitting = true
        view.endEditing(true)

        guard let words = enteredWords() else {
            isSubmitting = false
            showMnemonicAlert()
            return
        }

        validateWords(enteredWords: words)
    }

    private func showMnemonicAlert() {
        // a word is incorrect.
        showAlert(title: nil,
                  text: lang("InvalidMnemonic"),
                  button: lang("OK"))
    }

    public var isLoading: Bool = false {
        didSet {
            bottomActionsView.primaryButton.showLoading = isLoading
            view.isUserInteractionEnabled = !isLoading
            navigationItem.hidesBackButton = isLoading
            navigationItem.rightBarButtonItem?.isEnabled = !isLoading
            bottomActionsView.primaryButton.setTitle(
                isLoading ? lang("Please wait...") : lang("Continue"),
                for: .normal)
        }
    }
    
    // MARK: Validate words
    
    private func validateWords(enteredWords: EnteredWords) {
        Task { @MainActor in
            do {
                isLoading = true
                let wordsToImport: [String]
                switch enteredWords {
                case .privateKey(let words):
                    wordsToImport = words
                case .words12(let words), .words24(let words):
                    let ok = try await Api.validateMnemonic(mnemonic: words)
                    if ok {
                        wordsToImport = words
                    } else {
                        throw SdkError.message(.invalidMnemonic)
                    }
                }
                try await goNext(wordsToImport: wordsToImport)
            } catch {
                errorOccured(failure: error)
            }
        }
    }
    
    private func goNext(wordsToImport: [String]) async throws {
        let execution = try await introModel.onWordInputContinue(words: wordsToImport)
        switch execution {
        case .completed:
            break
        case .deferredToPasscode:
            isLoading = false
            isSubmitting = false
        }
    }

    public func errorOccured(failure: any Error) {
        if let error = failure as? SdkError {
            switch error {
            case .message(let message):
                switch message {
                case .serverError:
                    showNetworkAlert()
                case .invalidMnemonic:
                    showMnemonicAlert()
                default:
                    showAlert(error: failure)
                }
            case .apiReturnedError(_, let displayError, _):
                if displayError == .invalidMnemonic {
                    showMnemonicAlert()
                } else {
                    showAlert(error: failure)
                }
            case .sdkNotReady, .javaScriptException, .decoding, .invalidResponse, .unexpected:
                showAlert(error: failure)
            }
        } else {
            showAlert(error: failure)
        }
        isLoading = false
        isSubmitting = false
    }
    
    private enum EnteredWords {
        case words12([String])
        case words24([String])
        case privateKey([String])
    }

    private func enteredWords() -> EnteredWords? {
        var words = [String]()
        for wordInput in wordInputs.prefix(secretWordsMode.wordCount) {
            guard let word = wordInput.trimmedText else { break }
            words.append(word)
        }
        
        if let w = normalizeMnemonicPrivateKey(words) {
            return .privateKey(w)
        }
            
        switch (secretWordsMode, words.count) {
        case (.words12, 12):
            return .words12(words)
        case (.words24, 24):
            return .words24(words)
        default:
            return nil
        }
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let keyboardVisible = view.keyboardLayoutGuide.layoutFrame.minY < view.safeAreaLayoutGuide.layoutFrame.maxY - 1
        bottomActionLeading.constant = keyboardVisible ? 16 : 36
        bottomActionTrailing.constant = keyboardVisible ? -16 : -36
        bottomActionBottom.constant = keyboardVisible ? -16 : -max(2, 36 - view.safeAreaInsets.bottom)

        // Include the entire area covered by the button and keyboard. With
        // explicit insets there is no automatic safe-area contribution to subtract.
        let buttonTop = view.keyboardLayoutGuide.layoutFrame.minY + bottomActionBottom.constant - bottomActionsView.bounds.height
        let insets = UIEdgeInsets(
            top: view.safeAreaInsets.top,
            left: 0,
            bottom: max(0, view.bounds.height - buttonTop + 12),
            right: 0
        )
        if scrollView.contentInset != insets {
            let topInsetChange = insets.top - scrollView.contentInset.top
            let offset = CGPoint(x: 0, y: scrollView.contentOffset.y - topInsetChange)
            scrollView.contentInset = insets
            scrollView.verticalScrollIndicatorInsets = insets
            scrollView.setContentOffset(clampedContentOffset(offset), animated: false)
        }
        updateFloatingControls()
    }

    private func updateFloatingControls() {
        let navigationBarHeight = navigationController?.navigationBar.bounds.height ?? 44
        let pinnedTop = view.safeAreaInsets.top - navigationBarHeight + 4
        let naturalTop = wordsModeSegmentedControl.center.y - wordsModeSegmentedControl.bounds.height / 2
        // Keep its original layout space and only translate the control when it reaches the navbar.
        wordsModeSegmentedControl.transform = CGAffineTransform(
            translationX: 0,
            y: max(0, scrollView.contentOffset.y + pinnedTop - naturalTop)
        )
        navigationBackground?.alpha = calculateNavigationBarProgressiveBlurProgress(
            scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        )
        suggestionsView.presentationBounds = CGRect(
            x: view.safeAreaInsets.left + 16,
            y: view.safeAreaInsets.top + 4,
            width: view.safeAreaLayoutGuide.layoutFrame.width - 32,
            height: max(0, bottomActionsView.frame.minY - 12 - view.safeAreaInsets.top - 4)
        )
    }

    private func scrollToInput(_ input: WWordInput, alignFirstRow: Bool) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let firstRowOffset = wordsStackView1.frame.minY - firstWordTop
        var offset = scrollView.contentOffset.y
        if alignFirstRow {
            offset = firstRowOffset
        }
        let inputFrame = input.convert(input.bounds, to: scrollView)
        let visibleTop = firstWordTop
        let visibleBottom = bottomActionsView.frame.minY - 12
        if inputFrame.maxY - offset > visibleBottom {
            offset = inputFrame.maxY - visibleBottom
        } else if inputFrame.minY - offset < visibleTop {
            offset = inputFrame.minY - visibleTop
        }
        scrollView.setContentOffset(clampedContentOffset(CGPoint(x: 0, y: offset)), animated: true)
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let minimumOffset = -scrollView.contentInset.top
        let maximumOffset = max(minimumOffset,
                                scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
        return CGPoint(x: 0, y: min(max(offset.y, minimumOffset), maximumOffset))
    }

    private var firstWordTop: CGFloat {
        view.safeAreaInsets.top + 10
    }
}

extension ImportWalletVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        guard !isUpdatingWordsMode else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let input = wordInputs.first(where: { $0.textField.isFirstResponder }) else { return }
            scrollToInput(input, alignFirstRow: isInitialFocusScrollPending)
        }
    }

    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        view.setNeedsLayout()
    }
}

extension ImportWalletVC: WWordInputDelegate {
    
    public func wordInputDidBeginEditing(_ input: WWordInput) {
        guard !isUpdatingWordsMode else { return }
        let shouldAlignFirstRow = !hasBegunEditing
        hasBegunEditing = true
        isInitialFocusScrollPending = isInitialFocusScrollPending || shouldAlignFirstRow
        DispatchQueue.main.async { [weak self] in
            self?.scrollToInput(input, alignFirstRow: shouldAlignFirstRow)
        }
    }

    public func wordInputDidWantToCommitData(_ input: WWordInput) {
        if enteredWords() == nil {
            if let input = wordInputs.first(where: { $0.trimmedText?.isEmpty ?? true }) {
                input.textField.becomeFirstResponder()
            } else {
                dismissKeyboard()
            }
        } else {
            continuePressedAsync()
        }
    }
    
    public func textChanged() {
        bottomActionsView.primaryButton.isEnabled = enteredWords() != nil
    }
    
    public func wordInput(_ input: WWordInput, wantsPasteWords words: [String]) {
        _ = pasteWords(words, startingInput: input)
    }
}

extension ImportWalletVC: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFloatingControls()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isInitialFocusScrollPending = false
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isInitialFocusScrollPending = false
    }
}

// UIKit's navbar intercepts touches above the safe area. Forward only those that
// land on the sticky control, which always remains in the scroll view.
private final class StickyControlHitArea: UIView {
    private weak var target: UIView?

    init(target: UIView) {
        self.target = target
        super.init(frame: .zero)
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        target?.intrinsicContentSize ?? .zero
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let target, target.window != nil else { return nil }
        return target.hitTest(target.convert(point, from: self), with: event)
    }
}

private final class SecretWordsModeControl: UIControl {
    var selectedSegmentIndex = 0 {
        didSet { updateSelection() }
    }

    private let background = WCapsuleGlassBackgroundView(style: .header, cornerRadius: 20)
    private let stackView = UIStackView()
    private var buttons: [UIButton] = []
    private let titles = [lang("12 Words"), lang("24 Words")].map { localizedIntegerDigits(in: $0) }

    init() {
        super.init(frame: .zero)
        semanticContentAttribute = .forceLeftToRight
        setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(background)
        stackView.spacing = 2
        stackView.distribution = .fillEqually
        stackView.semanticContentAttribute = .forceLeftToRight
        addSubview(stackView)
        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.numberOfLines = 1
            button.layer.cornerRadius = 17
            button.layer.cornerCurve = .continuous
            button.accessibilityIdentifier = "mnemonicWordCount.\(index == 0 ? 12 : 24)"
            button.addAction(UIAction { [weak self] _ in
                self?.selectedSegmentIndex = index
                self?.sendActions(for: .valueChanged)
            }, for: .touchUpInside)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        let font = WTypography.uiFont(.subheadlineBold)
        let titleWidth = titles.map { ceil($0.size(withAttributes: [.font: font]).width) }.max() ?? 0
        return CGSize(width: (titleWidth + 32) * 2 + 8, height: 40)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        stackView.frame = bounds.insetBy(dx: 3, dy: 3)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateSelection()
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedSegmentIndex
            button.setTitleColor(selected ? tintColor : .label, for: .normal)
            button.backgroundColor = selected ? .tertiarySystemFill : .clear
            button.titleLabel?.font = WTypography.uiFont(selected ? .subheadlineBold : .subheadlineEmphasized)
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    let model = IntroModel(network: .mainnet, authMode: .requiresPasscodeSetup)
    WNavigationController(rootViewController: ImportWalletVC(introModel: model))
}
#endif
