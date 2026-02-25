//
//  WordDisplayVC.swift
//  UICreateWallet
//
//  Created by Sina on 4/14/23.
//

import UIKit
import SwiftUI
import WalletContext
import UIComponents

public class WordDisplayVC: CreateWalletBaseVC {

    let introModel: IntroModel
    let wordList: [String]
    
    var hostingController: UIHostingController<WordDisplayView>?

    public init(introModel: IntroModel, wordList: [String]) {
        self.introModel = introModel
        self.wordList = wordList
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    func setupViews() {
        
        navigationItem.title = wordList.count == 24 ? lang("24 Words") : lang("12 Words")
        if !canGoBack {
            addCloseNavigationItemIfNeeded()
        }
        
        hostingController = addHostingController(makeView(), constraints: .fill)
    }
    
    func makeView() -> WordDisplayView {
        WordDisplayView(
            introModel: introModel,
            words: wordList,
        )
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    LocalizationSupport.shared.setLanguageCode("ru")
    return WordDisplayVC(
        introModel: IntroModel(network: .mainnet, password: nil),
        wordList: [
            "word 1", "word 2", "word 3", "word 4",
            "word 5", "word 6", "word 7", "word 8",
            "word 9", "word 10", "word 11", "word 12",
            "word 13", "word 14", "word 15", "word 16",
            "word 17", "word 18", "word 19", "word 20",
            "word 21", "word 22", "wordjj23kdasl", "word 24"
        ]
    )
}
#endif
