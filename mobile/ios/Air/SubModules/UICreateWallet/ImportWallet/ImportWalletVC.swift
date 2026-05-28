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

public class ImportWalletVC: CreateWalletBaseVC {
    private let introModel: IntroModel
    private let scrollView = UIScrollView()
    private var wordInputs: [WWordInput] = []
    private let suggestionsView = WSuggestionsView()
    private var isSubmitting = false
    
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

        // 24 word inputs
        let wordsStackView1 = UIStackView()
        wordsStackView1.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView1.axis = .vertical
        wordsStackView1.spacing = 16
        
        let wordsStackView2 = UIStackView()
        wordsStackView2.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView2.axis = .vertical
        wordsStackView2.spacing = 16
        
        scrollView.addSubview(wordsStackView1)
        scrollView.addSubview(wordsStackView2)
        NSLayoutConstraint.activate([
            wordsStackView1.topAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 24),
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
            
            if wordInput.wordNumber == fieldsCount {
                wordInput.textField.returnKeyType = .done
            } else {
                wordInput.textField.returnKeyType = .next
            }
            
            // We allow user to submit after entering 12 words (no auto-switching to 13th text field)
            if wordInput.wordNumber == fieldsCount / 2 {
                wordInput.advancesOnSuggestionSelection = false
            }
            
            if i < fieldsCount / 2 {
                wordsStackView1.addArrangedSubview(wordInput)
            } else {
                wordsStackView2.addArrangedSubview(wordInput)
            }
            
            if let previousWorkInput {
                previousWorkInput.nextInput = wordInput
            }
            wordInputs.append(wordInput)
            previousWorkInput = wordInput
        }
        
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
    
    private func pasteWords(_ words: [String], startingInput input: WWordInput) -> Bool {
        guard !words.isEmpty else { return false }
        
        var input = input
        var lastInput = input
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

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc func pasteFromClipboard() {
        guard let firstInput = wordInputs.first else { return }
        
        if UIPasteboard.general.hasStrings, let value = UIPasteboard.general.string, !value.isEmpty {
            let words = value.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace }).map(String.init)
            
            // clean everything pasted so far
            for input in wordInputs {
                input.setText("", notifyDelegate: false, goToNextInput: false)
            }
            
            if !pasteWords(words, startingInput: firstInput) {
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
                        throw BridgeCallError.message(.invalidMnemonic, nil)
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
        if let error = failure as? BridgeCallError {
            switch error {
            case .message(let bridgeCallErrorMessages, _):
                switch bridgeCallErrorMessages {
                case .serverError:
                    showNetworkAlert()
                case .invalidMnemonic:
                    showMnemonicAlert()
                default:
                    showAlert(error: failure)
                }
            case .customMessage(let string, _):
                showUnknownErrorAlert(customText: string)
            case .unknown, .apiReturnedError:
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
        for wordInput in wordInputs {
            guard let word = wordInput.trimmedText else { break }
            words.append(word)
        }
        
        if let w = normalizeMnemonicPrivateKey(words) {
            return .privateKey(w)
        }
            
        return switch words.count {
        case 12:
            .words12(words)
        case 24:
            .words24(words)
        default:
            nil
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
        guard input.wordNumber == 12 || input.wordNumber == 24 else { return }
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
