//
//  WordCheckVC.swift
//  UICreateWallet
//
//  Created by Sina on 4/14/23.
//

import UIKit
import UIHome
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

class WordCheckVC: WViewController {

    var wordList: [String]
    var wordIndices: [Int]
    let passedPasscode: String?
    let isFirstWallet: Bool

    private var scrollView: UIScrollView!
    private var wordInputs: [WWordInput]!
    private var suggestionsView: WSuggestionsView!
    private var suggestionsViewBottomConstraint: NSLayoutConstraint!

    public init(wordList: [String],
                wordIndices: [Int],
                passedPasscode: String?) {
        self.wordList = wordList
        self.wordIndices = wordIndices
        self.passedPasscode = passedPasscode
        self.isFirstWallet = passedPasscode == nil
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        super.loadView()
        
        setupViews()
    }
    
    func setupViews() {
        // parent scrollView
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // hide keyboard on drag
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

        // header
        let headerView = HeaderView(animationName: "Test Time",
                                    animationPlaybackMode: .once,
                                    title: lang("Test Time!"),
                                    description: WStrings.WordCheck_ViewWords(wordIndices: wordIndices))
        scrollView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 0),
            headerView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 32),
            headerView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -32)
        ])
        
        #if DEBUG
        let g = UITapGestureRecognizer()
        g.numberOfTapsRequired = 2
        g.addTarget(self, action: #selector(createWalletAndContinue))
        headerView.isUserInteractionEnabled = true
        headerView.addGestureRecognizer(g)
        #endif

        suggestionsView = WSuggestionsView()
        view.addSubview(suggestionsView)
        suggestionsViewBottomConstraint = suggestionsView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            suggestionsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suggestionsViewBottomConstraint
        ])

        // 3 word inputs
        let wordsStackView = UIStackView()
        wordsStackView.translatesAutoresizingMaskIntoConstraints = false
        wordsStackView.axis = .vertical
        wordsStackView.spacing = 16
        scrollView.addSubview(wordsStackView)
        NSLayoutConstraint.activate([
            wordsStackView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 36),
            wordsStackView.leftAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leftAnchor, constant: 48),
            wordsStackView.rightAnchor.constraint(equalTo: scrollView.contentLayoutGuide.rightAnchor, constant: -48)
        ])
        let fieldsCount = 3
        wordInputs = []
        for i in 0 ..< fieldsCount {
            let wordInput = WWordInput(index: i,
                                       wordNumber: wordIndices[i] + 1,
                                       suggestionsView: suggestionsView,
                                       delegate: self)
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
                self.continuePressed()
            }
        )
        
        let bottomActionsView = BottomActionsView(primaryAction: continueAction, reserveSecondaryActionHeight: false)
        scrollView.addSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            bottomActionsView.topAnchor.constraint(equalTo: wordsStackView.bottomAnchor, constant: 16),
            bottomActionsView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            bottomActionsView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 48),
            bottomActionsView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -48),
        ])

        // listen for keyboard
        WKeyboardObserver.observeKeyboard(delegate: self)
    }
    
    func continuePressed() {
        for (i, index) in wordIndices.enumerated() {
            if wordInputs[i].trimmedText != wordList[index] {
                view.endEditing(true)
                showAlert()
                return
            }
        }
        // all the words are correct
        createWalletAndContinue()
    }
    
    @objc private func createWalletAndContinue() {
        if !isFirstWallet {
            view.isUserInteractionEnabled = false
            _createWallet(passcode: passedPasscode!, biometricsEnabled: nil) { [weak self] in
                guard let self else {return}
                view.isUserInteractionEnabled = true
            }
        } else {
            let nextVC = SetPasscodeVC(onCompletion: { biometricsEnabled, passcode, onResult in
                // set passcode flow completion
                self._createWallet(passcode: passcode, biometricsEnabled: biometricsEnabled, onResult: onResult)
            })
            navigationController?.pushViewController(nextVC, animated: true)
        }
    }
    
    private func _createWallet(passcode: String, biometricsEnabled: Bool?, onResult: @escaping () -> Void) {
        Task { @MainActor in
            do {
                _ = try await AccountStore.createWallet(network: .mainnet, words: wordList, passcode: passcode, version: nil)
                KeychainHelper.save(biometricPasscode: passcode)
                if let biometricsEnabled { // nil if not first wallet
                    AppStorageHelper.save(isBiometricActivated: biometricsEnabled)
                }
                self.viewWallet()
            } catch {
                showAlert(error: error)
                onResult()
            }
        }
    }
    
    private func viewWallet() {
        Task { @MainActor in
            guard WalletContextManager.delegate?.isWalletReady != true else {
                dismiss(animated: true)
                return
            }
            let homeVC = HomeTabBarController()
            AppActions.transitionToNewRootViewController(homeVC, animationDuration: 0.35)
        }
    }
    
    private func showAlert() {
        // a word is incorrect.
        showAlert(title: lang("Incorrect words"),
                  text: lang("The secret words you have entered do not match the ones in the list."),
                  button: lang("Try again"),
                  secondaryButton: lang("See words"),
                  secondaryButtonPressed: { [weak self] in
            // see words pressed
            self?.navigationController?.popViewController(animated: true)
        }, preferPrimary: false)
    }
}

extension WordCheckVC: WKeyboardObserverDelegate {
    func keyboardWillShow(info: WKeyboardDisplayInfo) {
        if scrollView.contentInset.bottom == 0 {
            scrollView.contentInset.bottom = info.height + 20
            UIView.animate(withDuration: 0.2, animations: {
                self.suggestionsViewBottomConstraint.constant = -info.height
            })
        } else {
            // it's just a keyboard height changed caused by pushing new vc with keyboard
        }
    }
    
    func keyboardWillHide(info: WKeyboardDisplayInfo) {
        scrollView.contentInset.bottom = 0
        UIView.animate(withDuration: 0.2, animations: {
            self.suggestionsViewBottomConstraint.constant = 0
        })
    }
}

extension WordCheckVC: WWordInputDelegate {
    func resignedFirstResponder() {
        continuePressed()
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    return UINavigationController(
        rootViewController: WordCheckVC(wordList: [
            "word 1", "word 2", "word 3", "word 4",
            "word 5", "word 6", "word 7", "word 8",
            "word 9", "word 10", "word 11", "word 12",
            "word 13", "word 14", "word 15", "word 16",
            "word 17", "word 18", "word 19", "word 20",
            "word 21", "word 22", "word 23", "word 24"
        ], wordIndices: [2, 5, 18], passedPasscode: nil)
    )
}
#endif
