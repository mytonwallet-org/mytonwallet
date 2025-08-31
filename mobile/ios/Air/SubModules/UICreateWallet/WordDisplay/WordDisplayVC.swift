//
//  WordDisplayVC.swift
//  UICreateWallet
//
//  Created by Sina on 4/14/23.
//

import UIKit
import WalletCore
import WalletContext
import UIHome
import UISettings
import UIComponents

class WordDisplayVC: RecoveryPhraseVC {

    let isFirstWallet: Bool
    let passedPasscode: String?

    init(wordList: [String], passedPasscode: String?) {
        self.isFirstWallet = passedPasscode == nil
        self.passedPasscode = passedPasscode
        super.init(wordList: wordList)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        let g = UITapGestureRecognizer()
        g.numberOfTapsRequired = 2
        g.addTarget(self, action: #selector(gotoWordCheck))
        headerView.isUserInteractionEnabled = true
        headerView.addGestureRecognizer(g)
        #endif
    }

    // called on done button press
    override func donePressed() {
        gotoWordCheck()
    }
    
    @objc func gotoWordCheck() {
        // select 3 random words
        var wordIndices: [Int] = []
        while wordIndices.count < 3 {
            let index = Int(arc4random_uniform(UInt32(wordList.count)))
            if !wordIndices.contains(index) {
                wordIndices.append(index)
            }
        }
        wordIndices.sort()
        
        // pass words to WordCheckVC
        let wordCheckVC = WordCheckVC(wordList: wordList,
                                      wordIndices: wordIndices,
                                      passedPasscode: passedPasscode)
        navigationController?.pushViewController(wordCheckVC, animated: true)
    }

}

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    return UINavigationController(
        rootViewController: WordDisplayVC(wordList: [
            "word 1", "word 2", "word 3", "word 4",
            "word 5", "word 6", "word 7", "word 8",
            "word 9", "word 10", "word 11", "word 12",
            "word 13", "word 14", "word 15", "word 16",
            "word 17", "word 18", "word 19", "word 20",
            "word 21", "word 22", "word 23", "word 24"
        ], passedPasscode: nil)
    )
}
#endif
