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

public class ImportWalletVC: WViewController {

    private let passedPasscode: String?

    private var scrollView: UIScrollView!
    private var wordInputs: [WWordInput]!
    private var suggestionsView: WSuggestionsView!

    lazy var importWalletVM = ImportWalletVM(importWalletVMDelegate: self)

    public init(passedPasscode: String?) {
        self.passedPasscode = passedPasscode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()

        setupViews()
    }

    public override var hideNavigationBar: Bool {
        true
    }

    private var headerView: HeaderView!
    private var bottomActionsView: BottomActionsView!

    func setupViews() {
        addNavigationBar(title: "",
                                       closeIcon: AccountStore.accountsById.count > 0,
                                       addBackButton: (navigationController?.viewControllers.count ?? 1) > 1 ? { [weak self] in
            guard let self else {return}
            navigationController?.popViewController(animated: true)
        } : nil)

        // parent scrollView
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self

        // hide keyboard on drag
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
        headerView = HeaderView(animationName: "Recovery Phrase",
                                    animationPlaybackMode: .once,
                                    title: lang("24 Secret Words"),
                                    description: lang("You can restore access to your wallet by entering 24 words you wrote when down you creating the wallet."))
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
        let wordsStackView = UIStackView()
        wordsStackView.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView.axis = .vertical
        wordsStackView.spacing = 16
        scrollView.addSubview(wordsStackView)
        NSLayoutConstraint.activate([
            wordsStackView.topAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 36),
            wordsStackView.leftAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leftAnchor, constant: 48),
            wordsStackView.rightAnchor.constraint(equalTo: scrollView.contentLayoutGuide.rightAnchor, constant: -48)
        ])
        let fieldsCount = 24
        wordInputs = [
        ]
        let sampleWallet: [String]
        #if DEBUG
        sampleWallet = [
        ]
        #else
        sampleWallet = []
        #endif
        for i in 0 ..< fieldsCount {
            let wordInput = WWordInput(index: i,
                                       wordNumber: i + 1,
                                       suggestionsView: suggestionsView,
                                       delegate: self)
            #if DEBUG
//            wordInput.textField.text = sampleWallet[i]
            #endif
            if i < fieldsCount - 1 {
                wordInput.textField.returnKeyType = .next
            } else {
                wordInput.textField.returnKeyType = .done
            }
            wordsStackView.addArrangedSubview(wordInput)
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
        scrollView.addSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            bottomActionsView.topAnchor.constraint(equalTo: wordsStackView.bottomAnchor, constant: 16),
            bottomActionsView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            bottomActionsView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 48),
            bottomActionsView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -48),
        ])

        bringNavigationBarToFront()

        // listen for keyboard
        WKeyboardObserver.observeKeyboard(delegate: self)
    }

    @objc func pasteFromClipboard() {
        if UIPasteboard.general.hasStrings, let value = UIPasteboard.general.string, !value.isEmpty {
            let words = value.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace }).map(String.init)
            if words.count != 24 && words.count != 12 {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            wordInputs.first?.textField.distributeWords(words)
            if words.count >= 24 {
                scrollView.scrollToBottom(animated: true)
            } else if words.count == 12 {
                scrollView.scrollToBottom(animated: true)
            }
        } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            showToast(message: lang("Clipboard empty"))
        }
        
    }

    private var words: [String] = []
    func continuePressed(scrollToBottom: Bool = true) {
        view.endEditing(true)
        if scrollToBottom {
            scrollView.scrollToBottom(animated: true)
        }

        // check if all the words are in the possibleWordList
        words = [String]()
        for wordInput in wordInputs {
            guard let word = wordInput.trimmedText else { break }
            words.append(word)
        }
        
        if words.count != 24 && words.count != 12 {
            showMnemonicAlert()
        }

        if let passedPasscode {
            importWalletVM._importWallet(enteredWords: words, passcode: passedPasscode)
        } else {
            importWalletVM.validateWords(enteredWords: words)
        }
    }

    private func showMnemonicAlert() {
        // a word is incorrect.
        showAlert(title: lang("Wrong Phrase"),
                  text: lang("Looks like you entered an invalid mnemonic phrase."),
                  button: lang("OK"))
    }

    private func showUnknownErrorAlert(customText: String? = nil) {
        showAlert(title: lang("Import failed"),
                  text: customText ?? lang("Please try again."),
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
}

extension ImportWalletVC: ImportWalletVMDelegate {
    public func goNext(didImport: Bool, wordsToImport: [String]?) {
        navigationController?.pushViewController(ImportSuccessVC(didImport: didImport, wordsToImport: wordsToImport), animated: true)
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
}

extension ImportWalletVC: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let navigationBar else { return }
        navigationBar.showSeparator = scrollView.contentOffset.y + scrollView.contentInset.top + view.safeAreaInsets.top > 0
        if scrollView.convert(headerView.frame.origin, to: navigationBar).y <= -123 + scrollView.contentInset.top {
            navigationBar.set(title: lang("24 Secret Words"), animated: true)
        } else {
            navigationBar.set(title: nil, animated: true)
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    return UINavigationController(rootViewController: ImportWalletVC(passedPasscode: nil))
}
#endif
