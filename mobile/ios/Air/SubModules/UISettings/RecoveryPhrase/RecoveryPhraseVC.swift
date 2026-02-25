//
//  RecoveryPhraseVC.swift
//  UISettings
//
//  Created by Sina on 5/4/23.
//

import UIKit
import WalletContext
import UIComponents

open class RecoveryPhraseVC: SettingsBaseVC {
    
    public var wordList: [String]

    var scrollView: UIScrollView!

    public init(wordList: [String]) {
        self.wordList = wordList
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func loadView() {
        super.loadView()
        
        setupViews()
    }
    
    public var headerView: HeaderView!
    
    func setupViews() {
        // parent scrollView
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
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

        addNavigationBar(
            title: "",
            addBackButton: { [weak self] in
                guard let self else {return}
                navigationController?.popViewController(animated: true)
            })

        scrollView.contentInset.top = navigationBarHeight
        scrollView.verticalScrollIndicatorInsets.top = navigationBarHeight
        scrollView.contentOffset.y = -navigationBarHeight

        // header
        headerView = HeaderView(animationName: "Recovery Phrase",
                                    animationPlaybackMode: .once,
                                    title: lang("Your Recovery Phrase"),
                                description: lang("$mnemonic_list_description").replacingOccurrences(of: "**", with: ""))
        scrollView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 0),
            headerView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 32),
            headerView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -32)
        ])

        // word list
        let wordListView = WordListView(words: wordList)
        scrollView.addSubview(wordListView)
        NSLayoutConstraint.activate([
            wordListView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 40),
            wordListView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 45),
            wordListView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -45),
        ])
        
        // bottom actions
        let proceedAction = BottomAction(
            title: lang("Done"),
            onPress: {
                self.donePressed()
            }
        )
        
        let bottomActionsView = BottomActionsView(primaryAction: proceedAction, reserveSecondaryActionHeight: false)
        scrollView.addSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            bottomActionsView.topAnchor.constraint(equalTo: wordListView.bottomAnchor, constant: 52),
            bottomActionsView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            bottomActionsView.leftAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.leftAnchor, constant: 48),
            bottomActionsView.rightAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.rightAnchor, constant: -48),
        ])

    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // We don't consider additional space under bottomActionsView, to make it fixed without any scroll on bigger iOS devices,
        //  and add this space on smaller devices to let button come up a little more and make user feel better :)
        let isDeviceHeightEnoughForAllContent = screenHeight >= scrollView.contentSize.height
        if !isDeviceHeightEnoughForAllContent {
            scrollView.contentInset.bottom = BottomActionsView.reserveHeight
        }
    }
    
    // called on done button press
    open func donePressed() {
        navigationController?.popViewController(animated: true)
    }

}

extension RecoveryPhraseVC: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationBar?.showSeparator = scrollView.contentOffset.y + scrollView.contentInset.top + view.safeAreaInsets.top > 0
        guard let headerView else {
            return
        }
        if scrollView.convert(headerView.frame.origin, to: navigationBar).y <= -123 + scrollView.contentInset.top {
            navigationBar?.set(title: lang("Your Recovery Phrase"), animated: true)
        } else {
            navigationBar?.set(title: nil, animated: true)
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: RecoveryPhraseVC(wordList: [
        "word 1", "word 2", "word 3", "wordassadsa4",
        "word 5", "word 6", "word 7", "word 8",
        "word 9", "word 10", "woradsdsad 11", "word 12",
        "word 13", "word 14", "word 15", "word 16",
        "word 17", "word 18", "word 19", "word 20",
        "word 21", "word 22", "word 23", "wosasddasrd"
    ]))
}
#endif
