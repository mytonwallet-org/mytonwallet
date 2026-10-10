import { wordlist } from '@ton/crypto/dist/mnemonic/wordlist';

// The shortest recovery phrase; shorter runs of wordlist words occur in ordinary text
const MIN_PHRASE_WORDS = 12;
// A mistyped word stays part of the phrase: up to this many words outside the wordlist, inside the phrase or at its ends
const MAX_MISTYPED_WORDS = 2;
const WORD_PATTERN = /\p{L}+/gu;
// Wordlist words are 3 to 8 Latin letters, and so is a mistyped one
const MISTYPED_WORD_PATTERN = /^[a-z]{3,8}$/;
// The number a phrase's first word is listed under, such as "1." or "(1)", and not the end of a longer number
const LEADING_NUMBER_PATTERN = /(?:^|\D)([#(]?\d{1,2}[.):]?\s*)$/u;
// A sentence ends at `.`, `!`, `?` or `…` before a space and a capitalized word; `;`, `:` and list numbers only separate
const SENTENCE_END_PATTERN = /[.!?…]\s/u;
const CAPITALIZED_WORD_PATTERN = /^\p{Lu}\p{Ll}/u;
const LIST_NUMBER_PATTERN = /[#(]?\d{1,2}[.):]/gu;

export const DEFAULT_SECRET_PHRASE_PLACEHOLDER = '[secret words removed and not sent]';

interface Token {
  start: number;
  end: number;
  text: string;
  word: string;
}

let secretPhraseWordList: ReadonlySet<string> | undefined;

/** The BIP39 English wordlist, which TON recovery phrases share */
export function getSecretPhraseWordList(): ReadonlySet<string> {
  secretPhraseWordList ??= new Set(wordlist);
  return secretPhraseWordList;
}

/**
 * Replaces every recovery phrase in the text with the placeholder: a run of at least 12 words of the BIP39 English
 * wordlist, in any case and separated by spaces, punctuation or list numbers, up to the end of a sentence.
 * Text without a phrase is returned unchanged.
 */
export function removeSecretPhrases(text: string, wordList: ReadonlySet<string>, placeholder: string) {
  const tokens: Token[] = [...text.matchAll(WORD_PATTERN)].map((match) => ({
    start: match.index,
    end: match.index + match[0].length,
    text: match[0],
    word: match[0].toLowerCase(),
  }));
  const spans: { start: number; end: number }[] = [];
  let first = 0;
  while (first < tokens.length) {
    if (!wordList.has(tokens[first].word)) {
      first += 1;
      continue;
    }
    let start = first;
    let last = first;
    let mistyped = 0;
    for (let index = first + 1; index < tokens.length && isJoined(text, tokens, index); index += 1) {
      if (wordList.has(tokens[index].word)) {
        last = index;
      } else if (
        mistyped < MAX_MISTYPED_WORDS
        && isMistypedWord(tokens[index], wordList)
        && wordList.has(tokens[index + 1]?.word ?? '')
        && isJoined(text, tokens, index + 1)
      ) {
        mistyped += 1;
      } else {
        break;
      }
    }
    // A phrase short of 12 words may have a mistyped first or last word
    if (last - start + 1 < MIN_PHRASE_WORDS) {
      if (
        mistyped < MAX_MISTYPED_WORDS
        && start > 0
        && isMistypedWord(tokens[start - 1], wordList)
        && isJoined(text, tokens, start)
      ) {
        start -= 1;
        mistyped += 1;
      }
      if (
        mistyped < MAX_MISTYPED_WORDS
        && last + 1 < tokens.length
        && isMistypedWord(tokens[last + 1], wordList)
        && isJoined(text, tokens, last + 1)
      ) {
        last += 1;
      }
    }
    if (last - start + 1 < MIN_PHRASE_WORDS) {
      first += 1;
      continue;
    }
    const leadingNumber = text.slice(0, tokens[start].start).match(LEADING_NUMBER_PATTERN)?.[1].length ?? 0;
    spans.push({ start: tokens[start].start - leadingNumber, end: tokens[last].end });
    first = last + 1;
  }

  return spans.reduceRight(
    (result, { start, end }) => `${result.slice(0, start)}${placeholder}${result.slice(end)}`,
    text,
  );
}

function isMistypedWord(token: Token, wordList: ReadonlySet<string>) {
  return !wordList.has(token.word) && MISTYPED_WORD_PATTERN.test(token.word);
}

// Whether the token continues the text before it rather than starting a new sentence
function isJoined(text: string, tokens: Token[], index: number) {
  const separator = text.slice(tokens[index - 1].end, tokens[index].start).replace(LIST_NUMBER_PATTERN, '');
  return !(SENTENCE_END_PATTERN.test(separator) && CAPITALIZED_WORD_PATTERN.test(tokens[index].text));
}
