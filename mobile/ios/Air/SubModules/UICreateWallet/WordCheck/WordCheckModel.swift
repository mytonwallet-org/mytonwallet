//
//  WordDisplayView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.09.2025.
//

import SwiftUI
import WalletContext
import UIComponents
import Perception

@Perceptible
final class WordCheckModel {
    
    @PerceptionIgnored
    var words: [WordAtIdx]
    @PerceptionIgnored
    var allWords: [String]
    
    init(words: [String], allWords: [String]) {
        let words = words.enumerated().map { WordAtIdx(idx: $0, word: $1) }
        self.words = words
        self.allWords = allWords
        self.tests = makeTest(includeWords: [], words: words, allWords: allWords)
    }
    
    var tests: [Test]
    var revealCorrect: Bool = false
    var showTryAgain: Bool = false
    var hideAll: Bool = false
    var interactionDisabled: Bool = false
    
    var allSelected: Bool { tests.allSatisfy { $0.selection != nil } }
    var allCorrect: Bool { tests.allSatisfy { $0.selection == $0.correctWord.word } }
    
    func resetKeepingIncorrect() {
        let incorrectWords = tests.filter { $0.selection != $0.correctWord.word }.map(\.correctWord)
        self.tests = makeTest(includeWords: incorrectWords, words: words, allWords: allWords)
        self.revealCorrect = false
        self.showTryAgain = true
    }
}

struct WordAtIdx: Equatable, Hashable, Identifiable {
    var idx: Int
    var word: String
    
    var id: Self { self }
}
 
struct Test: Identifiable {
    var correctWord: WordAtIdx
    var words: [String]
    var selection: String?
    
    var id: Int { correctWord.idx }
}

func makeTest(includeWords: [WordAtIdx], words: [WordAtIdx], allWords: [String]) -> [Test] {
    var testWords = includeWords
    let includeWordIndices = Set(includeWords.map(\.idx))
    testWords.append(contentsOf: words
        .filter { !includeWordIndices.contains($0.idx) }
        .shuffled()
        .prefix(3 - includeWords.count)
    )
    testWords.shuffle()
    var tests: [Test] = []
    for testWord in testWords {
        let letter = testWord.word[0]
        let candidates = allWords
            .filter { $0.hasPrefix(letter) && $0 != testWord.word }
            .shuffled()
            .prefix(3)
        let words = (candidates + [testWord.word]).shuffled()
        tests.append(
            Test(
                correctWord: testWord,
                words: words,
            )
        )
    }
    tests = tests.sorted(by: { $0.id < $1.id })
    return tests
}
