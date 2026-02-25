//
//  WordCheckVC.swift
//  UICreateWallet
//
//  Created by Sina on 4/14/23.
//

import UIKit
import UIPasscode
import UIComponents
import SwiftUI
import WalletContext

class WordCheckVC: CreateWalletBaseVC {

    private var introModel: IntroModel
    private var model: WordCheckModel
    
    private var hostingController: UIHostingController<WordCheckView>?
    
    public init(introModel: IntroModel, words: [String], allWords: [String]) {
        self.introModel = introModel
        self.model = WordCheckModel(words: words, allWords: allWords)
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
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    func makeView() -> WordCheckView {
        WordCheckView(
            introModel: introModel,
            model: model,
        )
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
    }
}


#if DEBUG
@available(iOS 18.0, *)
#Preview {
    WordCheckVC(
        introModel: IntroModel(network: .mainnet, password: nil),
        words: [
            "word 1", "word 2", "word 3", "word 4",
            "word 5", "word 6", "word 7", "word 8",
            "word 9", "word 10", "word 11", "word 12",
            "word 13", "word 14", "word 15", "word 16",
            "word 17", "word 18", "word 19", "word 20",
            "word 21", "word 22", "word 23", "word 24"
        ],
        allWords: [
            "word 1", "word 2", "word 3", "word 4",
            "word 5", "word 6", "word 7", "word 8",
            "word 9", "word 10", "word 11", "word 12",
            "word 13", "word 14", "word 15", "word 16",
            "word 17", "word 18", "word 19", "word 20",
            "word 21", "word 22", "word 23", "word 24"
        ]
    )
}
#endif
