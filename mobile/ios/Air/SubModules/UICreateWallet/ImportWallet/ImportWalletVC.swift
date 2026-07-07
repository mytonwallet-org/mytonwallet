//
//  ImportWalletVC.swift
//  UICreateWallet
//
//  Created by Sina on 4/21/23.
//

import UIKit
import UIPasscode
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
    
    private lazy var wordsModeSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [lang("12 Words"), lang("24 Words")])
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = SecretWordsMode.words12.segmentIndex
        control.apportionsSegmentWidthsByContent = false
        control.addTarget(self, action: #selector(wordsModeChanged), for: .valueChanged)
        return control
    }()

    private lazy var headerView = HeaderView(
        animationName: "animation_snitch",
        animationPlaybackMode: .once,
        title: lang("Enter Secret Words"),
        description: lang("$auth_import_mnemonic_description", arg1: langJoin(["12", "24"], .or)),
        animationSize: 96,
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

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isLoading {
            isSubmitting = false
            textChanged()
        }
    }

    private func setupViews() {
        navigationItem.title = nil
        if AccountStore.accountsById.count > 0 {
            addCloseNavigationItemIfNeeded()
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self

        scrollView.keyboardDismissMode = .interactive

        // add scrollView to view controller's main view
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            // scrollView
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leftAnchor.constraint(equalTo: view.leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: view.rightAnchor),
            // contentLayout
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: view.widthAnchor),
        ])

        headerView.isUserInteractionEnabled = true
        headerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))

        scrollView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 0),
            headerView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 32),
            headerView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -32)
        ])

        // `can not remember words` button
        let pasteButton = WButton(style: .clearBackground)
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.setTitle(lang("Paste from Clipboard"), for: .normal)
        pasteButton.addTarget(self, action: #selector(pasteFromClipboard), for: .touchUpInside)
        scrollView.addSubview(pasteButton)
        NSLayoutConstraint.activate([
            pasteButton.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            pasteButton.leftAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leftAnchor, constant: 48),
            pasteButton.rightAnchor.constraint(equalTo: scrollView.contentLayoutGuide.rightAnchor, constant: -48)
        ])

        wordsStackView1.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView1.axis = .vertical
        wordsStackView1.spacing = 16
        
        wordsStackView2.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView2.axis = .vertical
        wordsStackView2.spacing = 16
        
        scrollView.addSubview(wordsModeSegmentedControl)
        scrollView.addSubview(wordsStackView1)
        scrollView.addSubview(wordsStackView2)
        NSLayoutConstraint.activate([
            wordsModeSegmentedControl.topAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 16),
            wordsModeSegmentedControl.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 32),
            wordsModeSegmentedControl.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -32),
            wordsModeSegmentedControl.heightAnchor.constraint(equalToConstant: 36),

            wordsStackView1.topAnchor.constraint(equalTo: wordsModeSegmentedControl.bottomAnchor, constant: 24),
            wordsStackView2.topAnchor.constraint(equalTo: wordsStackView1.topAnchor),
            
            wordsStackView1.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 32),
            wordsStackView2.leadingAnchor.constraint(equalTo: wordsStackView1.trailingAnchor, constant: 16),
            wordsStackView2.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -32),
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
        
        scrollView.addSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            bottomActionsView.topAnchor.constraint(equalTo: wordsStackView1.bottomAnchor, constant: 24),
            bottomActionsView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            bottomActionsView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 32),
            bottomActionsView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -32),
        ])

        textChanged()

        WKeyboardObserver.observeKeyboard(delegate: self)
    }

    private func setWordsMode(_ mode: SecretWordsMode) {
        wordsModeSegmentedControl.selectedSegmentIndex = mode.segmentIndex
        guard secretWordsMode != mode else { return }

        secretWordsMode = mode
        UIView.performWithoutAnimation {
            updateWordInputsLayout()
            view.layoutIfNeeded()
        }
        textChanged()
    }

    private func updateWordInputsLayout() {
        let focusedInput = wordInputs.first { $0.textField.isFirstResponder }
        let activeWordCount = secretWordsMode.wordCount
        let columnWordCount = activeWordCount / 2

        for stackView in [wordsStackView1, wordsStackView2] {
            for view in stackView.arrangedSubviews {
                stackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }

        for (index, wordInput) in wordInputs.enumerated() {
            let isActive = index < activeWordCount
            wordInput.isHidden = !isActive
            wordInput.nextInput = nil
            wordInput.advancesOnSuggestionSelection = false
            wordInput.textField.returnKeyType = index == activeWordCount - 1 ? .done : .next
        }

        for index in 0 ..< activeWordCount {
            let wordInput = wordInputs[index]
            wordInput.isHidden = false
            if index < columnWordCount {
                wordsStackView1.addArrangedSubview(wordInput)
            } else {
                wordsStackView2.addArrangedSubview(wordInput)
            }
            wordInput.nextInput = index + 1 < activeWordCount ? wordInputs[index + 1] : nil
            wordInput.advancesOnSuggestionSelection = index + 1 < activeWordCount
        }

        if let focusedInput {
            if focusedInput.wordNumber <= activeWordCount {
                focusedInput.textField.becomeFirstResponder()
            } else {
                focusPreferredActiveInput()
            }
        }
    }

    private func focusPreferredActiveInput() {
        let activeInputs = wordInputs.prefix(secretWordsMode.wordCount)
        let targetInput = activeInputs.first { $0.trimmedText == nil } ?? activeInputs.last
        targetInput?.textField.becomeFirstResponder()
    }

    @objc private func wordsModeChanged(_ sender: UISegmentedControl) {
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

        if #available(iOS 17.0, *), let target = lastInput.frame(in: scrollView) {
            scrollView.scrollRectToVisible(target, animated: true)
        }
        
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
        scrollToBottomAction()

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

    private func showUnknownErrorAlert(customText: String? = nil) {
        showAlert(title: lang("Import failed"),
                  text: customText ?? lang("Please try again"),
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
    
    private func scrollToBottomAction() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let buttonFrame = self.scrollView.convert(self.bottomActionsView.bounds, from: self.bottomActionsView)
            self.scrollView.scrollRectToVisible(buttonFrame, animated: true)
        }
    }
}

extension ImportWalletVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        // info.endFrame is in screen coordinates; only count the portion that
        // actually overlaps this view so iPad modal/floating keyboards don't
        // add phantom inset.
        let viewFrameInScreen = view.convert(view.bounds, to: nil)
        let overlap = viewFrameInScreen.intersection(info.endFrame)
        let height = overlap.isNull ? 0 : overlap.height
        scrollView.contentInset.bottom = height + 16
    }

    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        scrollView.contentInset.bottom = 0
    }
}

extension ImportWalletVC: WWordInputDelegate {
    
    public func wordInputDidBeginEditing(_ input: WWordInput) {
        let activeWordCount = secretWordsMode.wordCount
        guard input.wordNumber == activeWordCount / 2 || input.wordNumber == activeWordCount else { return }
        scrollToBottomAction()
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
        navigationItem.title = scrollView.contentOffset.y + scrollView.adjustedContentInset.top > 80
            ? headerView.lblTitle.text
            : nil
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    let model = IntroModel(network: .mainnet, password: nil)
    WNavigationController(rootViewController: ImportWalletVC(introModel: model))
}
#endif
