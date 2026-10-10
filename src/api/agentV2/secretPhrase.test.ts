import { getSecretPhraseWordList, removeSecretPhrases } from './secretPhrase';

const WORD_LIST = getSecretPhraseWordList();
const PLACEHOLDER = '[removed]';
// Public test values that guard no funds: a TON phrase generated for tests and the BIP39 test vector for entropy
// c0ba5a8e914111210f2bd131f3d5e08d
const TON_PHRASE = 'creek aisle average raccoon february awkward thing cross morning guard monster lemon spy crystal '
  + 'gather switch noise index hub afraid ostrich urban since wisdom';
const BIP39_PHRASE = 'scheme spot photo card baby mountain device kick cradle pact join borrow';

function remove(text: string) {
  return removeSecretPhrases(text, WORD_LIST, PLACEHOLDER);
}

describe('removeSecretPhrases', () => {
  it('replaces a phrase inside a sentence and keeps the rest of the message', () => {
    expect(remove(`Вот моя сид-фраза: ${TON_PHRASE}. Проверь, всё ли в порядке с кошельком.`))
      .toBe('Вот моя сид-фраза: [removed]. Проверь, всё ли в порядке с кошельком.');
  });

  it('replaces a numbered phrase together with its list numbers', () => {
    const numbered = BIP39_PHRASE.split(' ').map((word, index) => `${index + 1}. ${word}`).join(' ');
    expect(remove(`My recovery phrase is ${numbered}. Can you restore it?`))
      .toBe('My recovery phrase is [removed]. Can you restore it?');
    const listed = BIP39_PHRASE.split(' ').map((word, index) => `(${index + 1}) ${word}`).join('\n');
    expect(remove(`Words:\n${listed}`)).toBe('Words:\n[removed]');
  });

  it('replaces a phrase in any case and with any separators', () => {
    expect(remove(BIP39_PHRASE.toUpperCase().split(' ').join(', '))).toBe(PLACEHOLDER);
    for (const separator of ['\n', '-', ';', '; ', '.', '. ', ': ']) {
      expect(remove(BIP39_PHRASE.split(' ').join(separator))).toBe(PLACEHOLDER);
    }
    expect(remove(BIP39_PHRASE.toUpperCase().split(' ').join('. '))).toBe(PLACEHOLDER);
    const numbered = BIP39_PHRASE.split(' ').map((word, index) => `${index + 1}) ${word};`).join(' ');
    expect(remove(numbered)).toBe(`${PLACEHOLDER};`);
  });

  it('replaces a phrase with up to two mistyped words', () => {
    expect(remove(BIP39_PHRASE.replace('mountain', 'mountian').replace('cradle', 'cradel'))).toBe(PLACEHOLDER);
    expect(remove(`${BIP39_PHRASE.replace('borrow', 'borow')}.`)).toBe(`${PLACEHOLDER}.`);
    expect(remove(`Мои слова: ${BIP39_PHRASE.replace('scheme', 'shceme')}`)).toBe(`Мои слова: ${PLACEHOLDER}`);
    expect(remove(BIP39_PHRASE.replace('scheme', 'shceme').replace('borrow', 'borow'))).toBe(PLACEHOLDER);
    // Three mistyped words split the 12 words into runs too short to be a phrase
    const three = BIP39_PHRASE.replace('spot', 'spto').replace('mountain', 'mountian').replace('cradle', 'cradel');
    expect(remove(three)).toBe(three);
  });

  it('replaces every phrase of a message and keeps a year before one', () => {
    expect(remove(`In 2024 I saved ${BIP39_PHRASE}. Потом: ${TON_PHRASE}.`))
      .toBe('In 2024 I saved [removed]. Потом: [removed].');
    expect(remove(`Saved in 2012 ${BIP39_PHRASE}`)).toBe('Saved in 2012 [removed]');
  });

  it('ends a phrase at sentence punctuation, though the next sentence starts with wordlist words', () => {
    expect(remove(`My words: ${BIP39_PHRASE}. Can you check them?`)).toBe('My words: [removed]. Can you check them?');
  });

  it('keeps ordinary messages, including fewer than 12 wordlist words in a row', () => {
    for (const text of [
      'Переведи 0.02 GRAM контакту «Лира QA»',
      'Can you check all my balance and also send some money to my brother because I need help today?',
      'Please explain how staking rewards work and which option is best for a long term plan.',
      'Show the price of TON, BTC and ETH for the last month.',
      BIP39_PHRASE.split(' ').slice(0, 11).join(' '),
      '',
    ]) {
      expect(remove(text)).toBe(text);
    }
  });
});
