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
    
    private var scrollView: UIScrollView!
    private var wordInputs: [WWordInput]!
    private var suggestionsView: WSuggestionsView!

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

    private var headerView: HeaderView!
    private var bottomActionsView: BottomActionsView!

    func setupViews() {
        addNavigationBar(
            title: "",
            closeIcon: AccountStore.accountsById.count > 0,
            addBackButton: (navigationController?.viewControllers.count ?? 1) > 1 ? weakifyGoBack() : nil
        )

        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self

        scrollView.keyboardDismissMode = .interactive

        // add scrollView to view controller's main view
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            // scrollView
            scrollView.topAnchor.constraint(equalTo: navigationBarAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leftAnchor.constraint(equalTo: view.leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: view.rightAnchor),
            // contentLayout
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: view.widthAnchor),
        ])

        // header
        headerView = HeaderView(
            animationName: "animation_snitch",
            animationPlaybackMode: .once,
            title: lang("Enter Secret Words"),
            description: lang("$auth_import_mnemonic_description", arg1: langJoin(["12", "24"], .or)),
            animationSize: 96,
        )
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

        suggestionsView = WSuggestionsView()

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
            
            wordsStackView1.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -90),
        ])
        let fieldsCount = 24
        
        wordInputs = [
        ]
        for i in 0 ..< fieldsCount {
            let wordInput = WWordInput(
                index: i,
                wordNumber: i + 1,
                suggestionsView: suggestionsView,
                delegate: self
            )
            if i < fieldsCount - 1 {
                wordInput.textField.returnKeyType = .next
            } else {
                wordInput.textField.returnKeyType = .done
            }
            if i < fieldsCount / 2 {
                wordsStackView1.addArrangedSubview(wordInput)
            } else {
                wordsStackView2.addArrangedSubview(wordInput)
            }
            // add word input to word inputs array to have a refrence
            wordInputs.append(wordInput)
        }
        
        // bottom action
        let continueAction = BottomAction(
            title: lang("Continue"),
            onPress: {
                self.continuePressed(scrollToBottom: false)
            }
        )

        bottomActionsView = BottomActionsView(primaryAction: continueAction, reserveSecondaryActionHeight: false)
        view.addSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            bottomActionsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomActionsView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 32),
            bottomActionsView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -32),
        ])

        let blurView = WBlurView()
        view.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: bottomActionsView.topAnchor, constant: -16),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blurView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor),
            blurView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor),
        ])
        
        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = WTheme.border
        view.addSubview(separatorView)
        NSLayoutConstraint.activate([
            separatorView.topAnchor.constraint(equalTo: blurView.topAnchor),
            separatorView.leftAnchor.constraint(equalTo: blurView.leftAnchor),
            separatorView.rightAnchor.constraint(equalTo: blurView.rightAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.33)
        ])

        
        view.bringSubviewToFront(bottomActionsView)
        
        bringNavigationBarToFront()

        textChanged()
        
        // listen for keyboard
        WKeyboardObserver.observeKeyboard(delegate: self)
    }

    @objc func pasteFromClipboard() {
        if UIPasteboard.general.hasStrings, let value = UIPasteboard.general.string, !value.isEmpty {
            let words = value.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace }).map(String.init)
            if !isValidImportWords(words) {
                Haptics.play(.error)
                if #available(iOS 17.0, *), let target = wordInputs.first?.frame(in: scrollView) {
                     scrollView.scrollRectToVisible(target, animated: true)
                }
            }
            wordInputs.first?.textField.distributeWords(words)
            textChanged()
        } else {
            Haptics.play(.lightTap)
            AppActions.showToast(message: lang("Clipboard empty"))
        }
        
    }

    private var words: [String] = []
    func continuePressed(scrollToBottom: Bool = true) {
        view.endEditing(true)
        if scrollToBottom {
            scrollView.scrollToBottom(animated: true)
        }

        // check if all the words are in the possibleWordList
        words = enteredWords()
        
        if !isValidImportWords(words) {
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
            bottomActionsView.primaryButton.setTitle(
                isLoading ? lang("Please wait...") : lang("Continue"),
                for: .normal)
        }
    }
    
    // MARK: Validate words
    
    func validateWords(enteredWords: [String]) {
        if let privateKeyWords = normalizeMnemonicPrivateKey(enteredWords) {
            goNext(didImport: false, wordsToImport: privateKeyWords)
            return
        }

        Task { @MainActor in
            do {
                isLoading = true
                let ok = try await Api.validateMnemonic(mnemonic: enteredWords)
                if ok {
                    goNext(didImport: false, wordsToImport: enteredWords)
                } else {
                    throw BridgeCallError.message(.invalidMnemonic, nil)
                }
            } catch {
                isLoading = false
                errorOccured(failure: error)
            }
        }
    }
    
    public func goNext(didImport: Bool, wordsToImport: [String]) {
        introModel.onWordInputContinue(words: wordsToImport)
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
    }
    
    private func enteredWords() -> [String] {
        var words = [String]()
        for wordInput in wordInputs {
            guard let word = wordInput.trimmedText else { break }
            words.append(word)
        }
        return words
    }
    
    private func isValidImportWords(_ words: [String]) -> Bool {
        words.count == 12 || words.count == 24 || isMnemonicPrivateKey(words)
    }
}

extension ImportWalletVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        scrollView.contentInset.bottom = info.height
    }

    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        scrollView.contentInset.bottom = 0
    }
}

extension ImportWalletVC: WWordInputDelegate {
    public func resignedFirstResponder() {
        continuePressed()
    }
    
    public func textChanged() {
        let enteredWords = enteredWords()
        bottomActionsView.primaryButton.isEnabled = isValidImportWords(enteredWords)
    }
}

extension ImportWalletVC: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationBarProgressiveBlur(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        if scrollView.convert(headerView.frame.origin, to: navigationBar).y <= -80 + scrollView.adjustedContentInset.top {
            navigationBar?.set(title: headerView.lblTitle.text, animated: true)
        } else {
            navigationBar?.set(title: nil, animated: true)
        }
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    let model = IntroModel(network: .mainnet, password: nil)
    WNavigationController(rootViewController: ImportWalletVC(introModel: model))
}
#endif
