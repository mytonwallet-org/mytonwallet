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

enum SecretWordsMode: Equatable {
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
    private let wordsContainerView = UIView()
    private let wordsStackView1 = UIStackView()
    private let wordsStackView2 = UIStackView()
    private var singleColumnConstraint: NSLayoutConstraint!
    private var twoColumnConstraint: NSLayoutConstraint!
    private var secretWordsMode = SecretWordsMode.words12
    private var isSubmitting = false
    
    private let bottomEdgeEffect = EdgeEffectView()
    private var navigationBackground: UIView?
    private var bottomActionLeading: NSLayoutConstraint!
    private var bottomActionTrailing: NSLayoutConstraint!
    private var bottomActionBottom: NSLayoutConstraint!
    private var isInitialFocusScrollPending = false
    private var isUpdatingWordsMode = false
    private var canContinueWithTwelveWords = false
    private var showsEditingNavigation = false
    private var showsContinueButton = true
    private weak var navigationHost: UIViewController?
    private var restingRightBarButtonItems: [UIBarButtonItem]?
    private var introductionViews: [UIView] = []

    private lazy var compactPasteItem: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "document.on.clipboard"), style: .plain,
                                  target: self, action: #selector(pasteFromClipboard))
        item.accessibilityLabel = lang("Paste from Clipboard")
        item.accessibilityIdentifier = "import_paste_compact"
        return item
    }()

    private lazy var wordsModeSegmentedControl: SecretWordsModeControl = {
        let control = SecretWordsModeControl()
        control.addTarget(self, action: #selector(wordsModeChanged), for: .valueChanged)
        return control
    }()
    private lazy var wordsModeTitleView = SecretWordsNavigationTitleView(control: wordsModeSegmentedControl)

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
        installNavigation(on: parent)
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
        installNavigation(on: self)

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

        headerView.lblTitle.accessibilityIdentifier = "import_title"
        headerView.isUserInteractionEnabled = true
        headerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))

        scrollView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: -16),
            headerView.leadingAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            headerView.trailingAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])

        let pasteButton = WButton(style: .primary)
        pasteButton.setTitle(lang("Paste from Clipboard"), for: .normal)
        pasteButton.setImage(UIImage(systemName: "document.on.clipboard"), for: .normal)
        if var configuration = pasteButton.configuration {
            configuration.cornerStyle = .capsule
            configuration.imagePadding = 6
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16)
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 32, bottom: 16, trailing: 32)
            pasteButton.configuration = configuration
        } else {
            pasteButton.layer.cornerRadius = 26
            pasteButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 32)
        }
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.accessibilityIdentifier = "import_paste"
        pasteButton.addTarget(self, action: #selector(pasteFromClipboard), for: .touchUpInside)
        scrollView.addSubview(pasteButton)
        NSLayoutConstraint.activate([
            pasteButton.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 40),
            pasteButton.centerXAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerXAnchor),
            pasteButton.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 32),
            pasteButton.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -32),
        ])

        let manualEntryLabel = UILabel()
        manualEntryLabel.text = lang("or enter manually")
        manualEntryLabel.applyTextStyle(.body)
        manualEntryLabel.textColor = .air.secondaryLabel
        manualEntryLabel.textAlignment = .center
        manualEntryLabel.numberOfLines = 0
        let manualEntry = UIStackView()
        manualEntry.translatesAutoresizingMaskIntoConstraints = false
        manualEntry.alignment = .center
        manualEntry.spacing = 12
        for index in 0 ..< 3 {
            if index == 1 {
                manualEntry.addArrangedSubview(manualEntryLabel)
            } else {
                let line = UIView()
                line.backgroundColor = .separator
                manualEntry.addArrangedSubview(line)
                line.widthAnchor.constraint(equalToConstant: 64).withPriority(.defaultHigh).isActive = true
                line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            }
        }
        scrollView.addSubview(manualEntry)
        NSLayoutConstraint.activate([
            manualEntry.topAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 40),
            manualEntry.centerXAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerXAnchor),
            manualEntry.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 32),
            manualEntry.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -32),
        ])
        introductionViews = [headerView, pasteButton, manualEntry]

        wordsStackView1.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView1.axis = .vertical
        wordsStackView1.spacing = 16
        wordsStackView1.semanticContentAttribute = .forceLeftToRight
        
        wordsStackView2.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView2.axis = .vertical
        wordsStackView2.spacing = 16
        wordsStackView2.semanticContentAttribute = .forceLeftToRight
        
        wordsContainerView.translatesAutoresizingMaskIntoConstraints = false
        wordsContainerView.alpha = 0.65
        scrollView.addSubview(wordsContainerView)
        wordsContainerView.addSubview(wordsStackView1)
        wordsContainerView.addSubview(wordsStackView2)
        singleColumnConstraint = wordsStackView1.rightAnchor.constraint(equalTo: wordsContainerView.rightAnchor)
        twoColumnConstraint = wordsStackView1.rightAnchor.constraint(equalTo: wordsContainerView.centerXAnchor, constant: -8)
        NSLayoutConstraint.activate([
            wordsContainerView.topAnchor.constraint(equalTo: manualEntry.bottomAnchor, constant: 24),
            wordsContainerView.centerXAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerXAnchor),
            wordsContainerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -64).withPriority(.defaultHigh),
            wordsContainerView.widthAnchor.constraint(lessThanOrEqualToConstant: 496),
            wordsContainerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            wordsStackView1.topAnchor.constraint(equalTo: wordsContainerView.topAnchor),
            wordsStackView2.topAnchor.constraint(equalTo: wordsStackView1.topAnchor),
            wordsStackView1.leftAnchor.constraint(equalTo: wordsContainerView.leftAnchor),
            singleColumnConstraint,
            wordsStackView2.leftAnchor.constraint(equalTo: wordsContainerView.centerXAnchor, constant: 8),
            wordsStackView2.rightAnchor.constraint(equalTo: wordsContainerView.rightAnchor),
            wordsStackView1.bottomAnchor.constraint(equalTo: wordsContainerView.bottomAnchor),
        ])
        
        let fieldsCount = 24
        var previousWorkInput: WWordInput?
        for i in 0 ..< fieldsCount {
            let wordInput = WWordInput(wordNumber: i + 1, suggestionsView: suggestionsView, delegate: self)
            wordInput.textField.accessibilityIdentifier = "import_word_\(i + 1)"
            
            if let previousWorkInput {
                previousWorkInput.nextInput = wordInput
            }
            wordInputs.append(wordInput)
            (i < 12 ? wordsStackView1 : wordsStackView2).addArrangedSubview(wordInput)
            if i >= 12 { wordInput.alpha = 0 }
            previousWorkInput = wordInput
        }
        updateWordInputsLayout()

        navigationBackground = addCustomNavigationBarBackground(color: .air.groupedBackground, inside: scrollView)
        navigationBackground?.alpha = 0

        bottomEdgeEffect.translatesAutoresizingMaskIntoConstraints = false
        bottomEdgeEffect.update(content: .air.groupedBackground, blur: true, alpha: 0.85, edge: .bottom, edgeSize: 48)
        view.addSubview(bottomEdgeEffect)
        bottomActionsView.primaryButton.accessibilityIdentifier = "import_continue"
        view.addSubview(bottomActionsView)
        bottomActionLeading = bottomActionsView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 36)
        bottomActionTrailing = bottomActionsView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -36)
        bottomActionBottom = bottomActionsView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -2)
        bottomActionLeading.priority = .defaultHigh
        bottomActionTrailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            bottomActionLeading,
            bottomActionTrailing,
            bottomActionBottom,
            bottomActionsView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            bottomActionsView.widthAnchor.constraint(lessThanOrEqualToConstant: 496),
            bottomEdgeEffect.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomEdgeEffect.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomEdgeEffect.topAnchor.constraint(equalTo: bottomActionsView.topAnchor, constant: -16),
            bottomEdgeEffect.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.addSubview(suggestionsView)
        suggestionsView.onSuggestionsChange = { [weak self] in
            guard let self else { return }
            self.updateContinueVisibility(animated: self.view.window != nil)
        }

        textChanged()

        WKeyboardObserver.observeKeyboard(delegate: self)
    }

    func setWordsMode(_ mode: SecretWordsMode) {
        wordsModeSegmentedControl.selectedSegmentIndex = mode.segmentIndex
        guard secretWordsMode != mode else { return }

        let hasTwelveWordPhrase = if case .words12 = enteredWords() { true } else { false }
        canContinueWithTwelveWords = mode == .words24 && hasTwelveWordPhrase
        let contentOffset = scrollView.contentOffset
        isUpdatingWordsMode = true
        isInitialFocusScrollPending = false
        secretWordsMode = mode
        view.layoutIfNeeded()
        updateWordInputsLayout()
        let animated = view.window != nil && !UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: animated ? 0.42 : 0, delay: 0, usingSpringWithDamping: 0.86,
                       initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.view.layoutIfNeeded()
        }
        let isExpanded = mode == .words24
        let firstVisibleRow = max(0, Int((scrollView.contentOffset.y + firstWordTop - wordsContainerView.frame.minY) / 64))
        for (row, input) in wordInputs.suffix(12).enumerated() {
            if isExpanded && input.alpha == 0 {
                input.transform = CGAffineTransform(translationX: 28, y: 6)
            }
            let delay = animated ? Double(min(8, max(0, row - firstVisibleRow))) * 0.025 : 0
            UIView.animate(withDuration: animated ? 0.42 : 0, delay: delay, usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                input.alpha = isExpanded ? 1 : 0
                input.transform = isExpanded || !animated ? .identity : CGAffineTransform(translationX: 20, y: 0)
            }
        }
        scrollView.setContentOffset(clampedContentOffset(contentOffset), animated: false)
        isUpdatingWordsMode = false
        updateFloatingControls()
        textChanged()
    }

    private func updateWordInputsLayout() {
        let focusedInput = wordInputs.first { $0.textField.isFirstResponder }
        let activeWordCount = secretWordsMode.wordCount
        NSLayoutConstraint.deactivate([singleColumnConstraint, twoColumnConstraint])
        (secretWordsMode == .words12 ? singleColumnConstraint : twoColumnConstraint).isActive = true
        wordsStackView2.isUserInteractionEnabled = secretWordsMode == .words24
        wordsStackView2.accessibilityElementsHidden = secretWordsMode == .words12

        for (index, wordInput) in wordInputs.enumerated() {
            wordInput.previousInput = nil
            wordInput.nextInput = nil
            wordInput.advancesOnSuggestionSelection = false
            wordInput.textField.returnKeyType = index == activeWordCount - 1 ? .done : .next
        }

        for index in 0 ..< activeWordCount {
            let wordInput = wordInputs[index]
            wordInput.previousInput = index > 0 ? wordInputs[index - 1] : nil
            wordInput.nextInput = index + 1 < activeWordCount ? wordInputs[index + 1] : nil
            wordInput.advancesOnSuggestionSelection = index + 1 < activeWordCount
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
        guard let mode = SecretWordsMode(segmentIndex: sender.selectedSegmentIndex), mode != secretWordsMode else { return }
        setWordsMode(mode)
        if canContinueWithTwelveWords, wordInputs.contains(where: { $0.textField.isFirstResponder }) {
            wordInputs[SecretWordsMode.words12.wordCount].textField.becomeFirstResponder()
        }
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
        canContinueWithTwelveWords = false
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
            wordsModeSegmentedControl.isUserInteractionEnabled = !isLoading
            compactPasteItem.isEnabled = !isLoading
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
        case (.words24, 12) where canContinueWithTwelveWords && wordInputs.dropFirst(12).allSatisfy({ $0.trimmedText == nil }):
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
        updateContinueVisibility(animated: view.window != nil)

        // Include the entire area covered by the button and keyboard. With
        // explicit insets there is no automatic safe-area contribution to subtract.
        let buttonTop = view.keyboardLayoutGuide.layoutFrame.minY + bottomActionBottom.constant - bottomActionsView.bounds.height
        // Tall iPad windows still need enough scroll space to reveal editing navigation without a software keyboard.
        let firstRowAlignmentInset = scrollView.bounds.height - firstWordTop - wordsContainerView.bounds.height
        let insets = UIEdgeInsets(
            top: view.safeAreaInsets.top,
            left: 0,
            bottom: max(0, view.bounds.height - buttonTop + 12, firstRowAlignmentInset),
            right: 0
        )
        if scrollView.contentInset != insets {
            let topInsetChange = insets.top - scrollView.contentInset.top
            let offset = CGPoint(x: 0, y: scrollView.contentOffset.y - topInsetChange)
            scrollView.contentInset = insets
            scrollView.verticalScrollIndicatorInsets = insets
            // Keyboard layout changes arrive throughout its animation. Reassigning
            // the offset on each frame would cancel the focus scroll.
            if topInsetChange != 0 || offset != clampedContentOffset(offset) {
                scrollView.setContentOffset(clampedContentOffset(offset), animated: false)
            }
        }
        updateFloatingControls()
    }

    private func updateFloatingControls() {
        guard wordsContainerView.bounds.height > 0 else { return }
        let fieldsTop = wordsContainerView.frame.minY - scrollView.contentOffset.y
        setEditingNavigationVisible(fieldsTop <= firstWordTop + (showsEditingNavigation ? 64 : 40))
        navigationBackground?.alpha = calculateNavigationBarProgressiveBlurProgress(
            scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        )
        let width = min(496, view.safeAreaLayoutGuide.layoutFrame.width - 32)
        suggestionsView.bottomPresentationFrame = usesKeyboardSuggestions ? CGRect(
            x: view.safeAreaLayoutGuide.layoutFrame.midX - width / 2,
            y: view.keyboardLayoutGuide.layoutFrame.minY - 16 - 44,
            width: width,
            height: 44
        ) : nil
        suggestionsView.presentationBounds = CGRect(
            x: view.safeAreaInsets.left + 16,
            y: view.safeAreaInsets.top + 4,
            width: view.safeAreaLayoutGuide.layoutFrame.width - 32,
            height: max(0, bottomActionsView.frame.minY - 12 - view.safeAreaInsets.top - 4)
        )
    }

    var usesKeyboardSuggestions: Bool {
        traitCollection.horizontalSizeClass == .compact
            && traitCollection.verticalSizeClass == .regular
            && view.keyboardLayoutGuide.layoutFrame.height > view.safeAreaInsets.bottom + 100
    }

    private func installNavigation(on host: UIViewController) {
        if navigationHost !== host {
            navigationHost = host
            restingRightBarButtonItems = host.navigationItem.rightBarButtonItems
        }
        host.navigationItem.titleView = wordsModeTitleView
        wordsModeSegmentedControl.alpha = showsEditingNavigation ? 1 : 0
        wordsModeTitleView.isUserInteractionEnabled = showsEditingNavigation
        wordsModeTitleView.accessibilityElementsHidden = !showsEditingNavigation
    }

    private func setEditingNavigationVisible(_ visible: Bool) {
        guard showsEditingNavigation != visible else { return }
        showsEditingNavigation = visible
        wordsModeTitleView.isUserInteractionEnabled = visible
        wordsModeTitleView.accessibilityElementsHidden = !visible
        for introductionView in introductionViews {
            introductionView.isUserInteractionEnabled = !visible
            introductionView.accessibilityElementsHidden = visible
        }
        let animated = view.window != nil && !UIAccessibility.isReduceMotionEnabled
        let item = (navigationHost ?? self).navigationItem
        item.setRightBarButtonItems(visible ? [compactPasteItem] : restingRightBarButtonItems, animated: animated)
        UIView.animate(withDuration: animated ? 0.28 : 0, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            self.wordsModeSegmentedControl.alpha = visible ? 1 : 0
            self.wordsModeSegmentedControl.transform = visible || !animated ? .identity : CGAffineTransform(translationX: 0, y: 8)
            self.introductionViews.forEach { $0.alpha = visible ? 0 : 1 }
        }
    }

    private func updateContinueVisibility(animated: Bool) {
        let visible = !usesKeyboardSuggestions || (enteredWords() != nil && !suggestionsView.hasSuggestions) || isLoading
        guard showsContinueButton != visible else { return }
        showsContinueButton = visible
        bottomActionsView.isUserInteractionEnabled = visible
        bottomActionsView.accessibilityElementsHidden = !visible
        let animated = animated && !UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: animated ? 0.32 : 0, delay: 0, usingSpringWithDamping: 0.88,
                       initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.bottomActionsView.alpha = visible ? 1 : 0
            self.bottomActionsView.transform = visible || !animated ? .identity : CGAffineTransform(translationX: 0, y: 12)
        }
    }

    private func scrollToInput(_ input: WWordInput, alignFirstRow: Bool) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let firstRowOffset = wordsContainerView.frame.minY - firstWordTop
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
        scrollView.setContentOffset(clampedContentOffset(CGPoint(x: 0, y: offset)), animated: !UIAccessibility.isReduceMotionEnabled)
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
        let shouldAlignFirstRow = !showsEditingNavigation
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25) {
            self.wordsContainerView.alpha = 1
        }
        isInitialFocusScrollPending = isInitialFocusScrollPending || shouldAlignFirstRow
        DispatchQueue.main.async { [weak self] in
            self?.scrollToInput(input, alignFirstRow: shouldAlignFirstRow)
        }
    }

    public func wordInputDidWantToCommitData(_ input: WWordInput) {
        if enteredWords() == nil {
            if let input = wordInputs.prefix(secretWordsMode.wordCount).first(where: { $0.trimmedText == nil }) {
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
        updateContinueVisibility(animated: view.window != nil)
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

private final class SecretWordsNavigationTitleView: UIView {
    private let control: UIView

    init(control: UIView) {
        self.control = control
        super.init(frame: .zero)
        addSubview(control)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        control.intrinsicContentSize
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        control.bounds = CGRect(origin: .zero, size: bounds.size)
        control.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

private final class SecretWordsModeControl: UIControl {
    var selectedSegmentIndex = 0 {
        didSet {
            guard oldValue != selectedSegmentIndex else { return }
            updateSelection()
            UIView.animate(withDuration: window != nil && !UIAccessibility.isReduceMotionEnabled ? 0.3 : 0,
                           delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.layoutIfNeeded()
            }
        }
    }

    private let background = WCapsuleGlassBackgroundView(style: .header, cornerRadius: 20)
    private let selectionView = UIView()
    private let stackView = UIStackView()
    private var buttons: [UIButton] = []
    private let titles = [lang("12 Words"), lang("24 Words")].map { localizedIntegerDigits(in: $0) }

    init() {
        super.init(frame: .zero)
        semanticContentAttribute = .forceLeftToRight
        setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(background)
        selectionView.backgroundColor = .tertiarySystemFill
        selectionView.layer.cornerRadius = 17
        selectionView.layer.cornerCurve = .continuous
        selectionView.isUserInteractionEnabled = false
        addSubview(selectionView)
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
            button.accessibilityIdentifier = "import_mode_\(index == 0 ? 12 : 24)"
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
        stackView.layoutIfNeeded()
        if buttons.indices.contains(selectedSegmentIndex) {
            selectionView.frame = buttons[selectedSegmentIndex].convert(buttons[selectedSegmentIndex].bounds, to: self)
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateSelection()
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedSegmentIndex
            button.setTitleColor(selected ? tintColor : .label, for: .normal)
            button.titleLabel?.font = WTypography.uiFont(selected ? .subheadlineBold : .subheadlineEmphasized)
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
        setNeedsLayout()
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    let model = IntroModel(network: .mainnet, authMode: .requiresPasscodeSetup)
    WNavigationController(rootViewController: ImportWalletVC(introModel: model))
}
#endif
