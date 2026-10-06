import type { UserSwapToken, UserToken } from '../global/types';
import type { LangFn } from './langProvider';

import getChainNetworkName from './swap/getChainNetworkName';
import { getDisplayOrderedChains, getTrustedUsdtSlugs } from './chain';
import { getChainBySlug, getTokenName } from './tokens';

export type TokenType = UserToken | UserSwapToken;

type FieldKind = 'identifier' | 'address' | 'symbol' | 'title' | 'alias' | 'keyword';

// Ranking weights in this file are only compared with each other, so only their order matters.
// Equal weights, such as `symbol` and `title` in `FIELD_PRIORITY`, rank as ties.
enum MatchKind {
  Fuzzy = 100,
  Substring = 200,
  WordPrefix = 300,
  ExactWord = 400,
  PhrasePrefix = 500,
  ExactPhrase = 600,
  ExactIdentifier = 700,
}

enum RelevanceBand {
  Weak,
  Partial,
  Term,
  Phrase,
  ExactName,
  ExactIdentifier,
}

enum TrustTier {
  Unknown,
  Established,
  Curated,
}

interface NormalizedText {
  phrases: string[];
  /** Each term lists its spellings: the original one and, for Cyrillic text, the transliterated one */
  terms: string[][];
}

interface NormalizedValue {
  text: NormalizedText;
  identifier: string;
}

interface SearchField extends NormalizedValue {
  kind: FieldKind;
}

interface SearchQuery extends NormalizedValue {
  isMultiword: boolean;
  isExactIdentifierRequired: boolean;
}

interface MatchCandidate {
  kind: MatchKind;
  fieldKind: FieldKind;
}

interface FieldsMatch {
  match: MatchCandidate;
  matchedTermCount: number;
  wordMatchCount: number;
}

interface SearchHit<T extends TokenType> extends FieldsMatch {
  token: T;
  trustedUsdtPriority: number;
  personalPriority: number;
  baseCurrencyValue: number;
  trustTier: TrustTier;
}

const FIELD_PRIORITY: Record<FieldKind, number> = {
  identifier: 900,
  address: 850,
  symbol: 700,
  title: 700,
  alias: 500,
  keyword: 300,
};
const IDENTIFIER_FIELD_KINDS = new Set<FieldKind>(['identifier', 'address']);

const MIN_SUBSTRING_LENGTH = 2;
const MIN_FUZZY_LENGTH = 4;
const LEADING_GRAM_LENGTH = 2;
const EXACT_IDENTIFIER_QUERY_MIN_LENGTH = 24;

const HELD_PRIORITY = 1400;
const TRACKED_PRIORITY = 1300;
const POPULAR_PRIORITY = 600;

const COMBINING_MARK_REGEX = /\p{Mn}/gu;
const NON_WORD_REGEX = /[^\p{L}\p{M}\p{N}]+/u;
const NON_ASCII_REGEX = /\P{ASCII}/u;
const WHITESPACE_REGEX = /\s/;
const CYRILLIC_REGEX = /[а-яєіґ]/g;

// Only Cyrillic is transliterated: JS has no ICU transliterator for other scripts
const CYRILLIC_TO_LATIN: Record<string, string> = {
  а: 'a',
  б: 'b',
  в: 'v',
  г: 'g',
  д: 'd',
  е: 'e',
  ж: 'z',
  з: 'z',
  и: 'i',
  к: 'k',
  л: 'l',
  м: 'm',
  н: 'n',
  о: 'o',
  п: 'p',
  р: 'r',
  с: 's',
  т: 't',
  у: 'u',
  ф: 'f',
  х: 'h',
  ц: 'c',
  ч: 'c',
  ш: 's',
  щ: 's',
  ъ: 'ʺ',
  ы: 'y',
  ь: 'ʹ',
  э: 'e',
  ю: 'u',
  я: 'a',
  є: 'e',
  і: 'i',
  ґ: 'g',
};

const STOP_WORDS = new Set([
  'a', 'an', 'are', 'as', 'at', 'be', 'by', 'can', 'could', 'do', 'does',
  'for', 'from', 'how', 'i', 'in', 'is', 'it', 'of', 'on', 'or', 'the',
  'to', 'was', 'were', 'what', 'when', 'where', 'which', 'who', 'why', 'with',
  'а', 'в', 'во', 'для', 'и', 'из', 'как', 'какие', 'какой', 'когда',
  'кто', 'ли', 'на', 'о', 'об', 'от', 'по', 'почему', 'с', 'со',
  'такое', 'у', 'что', 'это',
].map(normalizeIdentifier));

// Token strings repeat across price and balance updates, so each one is normalized once per session
const normalizedValueCache = new Map<string, NormalizedValue>();
// Fields are built once per token object, since token objects survive between keystrokes.
// A language switch replaces the `lang` function, which resets the cache.
let fieldsCache = new WeakMap<TokenType, SearchField[]>();
let fieldsCacheLang: LangFn | undefined;

/** Filters and ranks tokens with an approach inspired by the iOS token search (`WalletCoreTokenSearch`) */
export function findTokensByQuery<T extends TokenType>(
  lang: LangFn,
  tokens: T[],
  query: string,
  trackedSlugs?: string[],
): T[] {
  const searchQuery = prepareQuery(query);
  if (!searchQuery.text.terms.length) return [];

  const documents = tokens.map((token) => ({ token, fields: getFields(lang, token) }));
  const leadingGrams = searchQuery.text.terms.flat().map((spelling) => spelling.slice(0, LEADING_GRAM_LENGTH));
  let hits = findHits(
    documents.filter(({ fields }) => fields.some((field) => getHasAnyGram(field, leadingGrams))),
    searchQuery,
    trackedSlugs,
  );

  // A typo in the leading characters escapes the gram filter, so typo recovery scans every token
  if (!hits.length && !searchQuery.isExactIdentifierRequired && getHasFuzzyTerm(searchQuery)) {
    hits = findHits(documents, searchQuery, trackedSlugs);
  }

  return hits.sort((a, b) => compareHits(b, a)).map(({ token }) => token);
}

function prepareQuery(query: string): SearchQuery {
  const trimmedQuery = query.trim();
  const text = normalizeText(query);
  const hasWhitespace = WHITESPACE_REGEX.test(trimmedQuery);

  return {
    text,
    identifier: normalizeIdentifier(query),
    isMultiword: text.terms.length > 1 && hasWhitespace,
    // Long unbroken input is an address or another identifier, so word fragments must not match it
    isExactIdentifierRequired: trimmedQuery.length >= EXACT_IDENTIFIER_QUERY_MIN_LENGTH && !hasWhitespace,
  };
}

function getFields(lang: LangFn, token: TokenType) {
  if (lang !== fieldsCacheLang) {
    fieldsCache = new WeakMap();
    fieldsCacheLang = lang;
  }

  let fields = fieldsCache.get(token);
  if (!fields) {
    fields = buildFields(lang, token);
    fieldsCache.set(token, fields);
  }

  return fields;
}

function buildFields(lang: LangFn, token: TokenType): SearchField[] {
  const values: [string | undefined, FieldKind][] = [
    [getTokenName(lang, token), 'title'],
    [token.name, 'alias'],
    [token.localizedName, 'alias'],
    [token.symbol, 'symbol'],
    [token.slug, 'identifier'],
    [token.tokenAddress, 'address'],
    [token.label, 'alias'],
    [getChainNetworkName(token.chain), 'keyword'],
    [token.chain, 'keyword'],
    ...(token.keywords ?? []).map((keyword): [string, FieldKind] => [keyword, 'keyword']),
  ];

  const fields: SearchField[] = [];
  for (const [value, kind] of values) {
    const trimmedValue = value?.trim();
    if (trimmedValue) {
      fields.push({ kind, ...normalizeValue(trimmedValue) });
    }
  }

  return fields;
}

function getHasAnyGram(field: SearchField, grams: string[]) {
  return grams.some((gram) => (
    field.identifier.includes(gram) || field.text.phrases.some((phrase) => phrase.includes(gram))
  ));
}

function getHasFuzzyTerm(query: SearchQuery) {
  return query.text.terms.some((term) => (
    !getIsStopWord(term, query) && term.some((spelling) => spelling.length >= MIN_FUZZY_LENGTH)
  ));
}

function findHits<T extends TokenType>(
  documents: { token: T; fields: SearchField[] }[],
  query: SearchQuery,
  trackedSlugs?: string[],
) {
  const hits: SearchHit<T>[] = [];
  for (const { token, fields } of documents) {
    const fieldsMatch = matchFields(fields, query);
    if (fieldsMatch) {
      hits.push({ token, ...fieldsMatch, ...buildRankSignals(token, trackedSlugs) });
    }
  }

  return hits;
}

function buildRankSignals(token: TokenType, trackedSlugs?: string[]) {
  const isPopular = 'isPopular' in token && token.isPopular;

  let personalPriority = 0;
  if (token.amount > 0n) {
    personalPriority = HELD_PRIORITY;
  } else if (trackedSlugs?.includes(token.slug)) {
    personalPriority = TRACKED_PRIORITY;
  } else if (isPopular) {
    personalPriority = POPULAR_PRIORITY;
  }

  let trustTier = TrustTier.Unknown;
  if (isPopular) {
    trustTier = TrustTier.Curated;
  } else if (token.priceUsd > 0) {
    trustTier = TrustTier.Established;
  }

  const chains = getDisplayOrderedChains();

  return {
    trustedUsdtPriority: getTrustedUsdtSlugs().has(token.slug)
      ? chains.length - chains.indexOf(getChainBySlug(token.slug))
      : 0,
    personalPriority,
    baseCurrencyValue: Math.max(0, Number(token.totalValue)) || 0,
    trustTier,
  };
}

function matchFields(fields: SearchField[], query: SearchQuery): FieldsMatch | undefined {
  const termCount = query.text.terms.length;
  const fullCoverage = { matchedTermCount: termCount, wordMatchCount: termCount };

  const identifierField = fields.find((field) => (
    IDENTIFIER_FIELD_KINDS.has(field.kind) && field.identifier === query.identifier
  ));
  if (identifierField) {
    return { match: { kind: MatchKind.ExactIdentifier, fieldKind: identifierField.kind }, ...fullCoverage };
  }
  if (query.isExactIdentifierRequired) return undefined;

  const phraseMatch = findPhraseMatch(fields, query);
  if (phraseMatch && getRelevanceBand(phraseMatch) >= RelevanceBand.Phrase) {
    return { match: phraseMatch, ...fullCoverage };
  }

  const termMatches: MatchCandidate[] = [];
  let wordMatchCount = 0;
  let hasMeaningfulMatch = false;
  for (const term of query.text.terms) {
    const isStopWord = getIsStopWord(term, query);
    const termMatch = findTermMatch(term, fields, isStopWord);
    if (!termMatch) continue;

    termMatches.push(termMatch.match);
    if (termMatch.hasWordMatch) wordMatchCount += 1;
    hasMeaningfulMatch ||= !isStopWord;
  }

  const strongestMatch = hasMeaningfulMatch ? termMatches.reduce(pickBetterCandidate) : undefined;
  // Chain and keyword phrases must not mask stronger name or symbol matches
  if (phraseMatch && (!strongestMatch || compareCandidates(strongestMatch, phraseMatch) < 0)) {
    return { match: phraseMatch, ...fullCoverage };
  }
  if (!strongestMatch) return undefined;

  return { match: strongestMatch, matchedTermCount: termMatches.length, wordMatchCount };
}

function findPhraseMatch(fields: SearchField[], query: SearchQuery) {
  let best: MatchCandidate | undefined;
  for (const field of fields) {
    if (IDENTIFIER_FIELD_KINDS.has(field.kind)) continue;

    for (const queryPhrase of query.text.phrases) {
      for (const fieldPhrase of field.text.phrases) {
        let kind: MatchKind | undefined;
        if (fieldPhrase === queryPhrase) {
          kind = MatchKind.ExactPhrase;
        } else if (fieldPhrase.startsWith(queryPhrase)) {
          kind = MatchKind.PhrasePrefix;
        }

        if (kind) {
          best = pickBetterCandidate(best, { kind, fieldKind: field.kind });
        }
      }
    }
  }

  return best;
}

function findTermMatch(term: string[], fields: SearchField[], isExactWordRequired: boolean) {
  let best: MatchCandidate | undefined;
  let hasWordMatch = false;
  for (const field of fields) {
    if (IDENTIFIER_FIELD_KINDS.has(field.kind)) continue;

    for (const querySpelling of term) {
      for (const fieldTerm of field.text.terms) {
        for (const fieldSpelling of fieldTerm) {
          const kind = getMatchKind(querySpelling, fieldSpelling, isExactWordRequired);
          if (!kind) continue;

          hasWordMatch ||= kind >= MatchKind.WordPrefix;
          best = pickBetterCandidate(best, { kind, fieldKind: field.kind });
        }
      }
    }
  }

  return best && { match: best, hasWordMatch };
}

function getMatchKind(query: string, candidate: string, isExactWordRequired: boolean) {
  if (candidate === query) return MatchKind.ExactWord;
  if (isExactWordRequired) return undefined;
  if (candidate.startsWith(query)) return MatchKind.WordPrefix;
  if (query.length >= MIN_SUBSTRING_LENGTH && candidate.includes(query)) return MatchKind.Substring;
  if (
    query.length >= MIN_FUZZY_LENGTH
    && candidate.length >= MIN_FUZZY_LENGTH
    && getIsOneEditAway(query, candidate)
  ) {
    return MatchKind.Fuzzy;
  }

  return undefined;
}

function getIsStopWord(term: string[], query: SearchQuery) {
  return query.isMultiword && STOP_WORDS.has(term[0]);
}

function compareHits<T extends TokenType>(a: SearchHit<T>, b: SearchHit<T>) {
  return getRelevanceBand(a.match) - getRelevanceBand(b.match)
    || a.wordMatchCount - b.wordMatchCount
    || a.matchedTermCount - b.matchedTermCount
    // Trusted USDT outranks equally relevant look-alikes, including ones the user holds
    || a.trustedUsdtPriority - b.trustedUsdtPriority
    || a.match.kind - b.match.kind
    || a.personalPriority - b.personalPriority
    || a.baseCurrencyValue - b.baseCurrencyValue
    || a.trustTier - b.trustTier
    || FIELD_PRIORITY[a.match.fieldKind] - FIELD_PRIORITY[b.match.fieldKind]
    || Number(a.token.slug < b.token.slug) - Number(a.token.slug > b.token.slug);
}

function pickBetterCandidate(best: MatchCandidate | undefined, candidate: MatchCandidate) {
  return !best || compareCandidates(candidate, best) > 0 ? candidate : best;
}

function compareCandidates(a: MatchCandidate, b: MatchCandidate) {
  return getRelevanceBand(a) - getRelevanceBand(b)
    || a.kind - b.kind
    || FIELD_PRIORITY[a.fieldKind] - FIELD_PRIORITY[b.fieldKind];
}

function getRelevanceBand({ kind, fieldKind }: MatchCandidate) {
  if (kind === MatchKind.ExactIdentifier) return RelevanceBand.ExactIdentifier;
  if (fieldKind === 'keyword') return RelevanceBand.Weak;

  switch (kind) {
    case MatchKind.ExactPhrase:
      return RelevanceBand.ExactName;
    case MatchKind.PhrasePrefix:
      return RelevanceBand.Phrase;
    case MatchKind.ExactWord:
    case MatchKind.WordPrefix:
      return RelevanceBand.Term;
    default:
      return RelevanceBand.Partial;
  }
}

/** Whether one substitution, insertion or deletion turns one string into the other */
function getIsOneEditAway(left: string, right: string) {
  if (Math.abs(left.length - right.length) > 1) return false;

  let index = 0;
  while (index < left.length && left[index] === right[index]) index++;

  const leftTail = left.slice(index + 1);
  const rightTail = right.slice(index + 1);

  return leftTail === rightTail || leftTail === right.slice(index) || left.slice(index) === rightTail;
}

function normalizeValue(value: string) {
  let normalizedValue = normalizedValueCache.get(value);
  if (!normalizedValue) {
    normalizedValue = { text: normalizeText(value), identifier: normalizeIdentifier(value) };
    normalizedValueCache.set(value, normalizedValue);
  }

  return normalizedValue;
}

function normalizeText(value: string): NormalizedText {
  const canonical = normalizeWords(value);
  if (!canonical) return { phrases: [], terms: [] };

  return {
    phrases: buildSpellings(canonical),
    terms: canonical.split(' ').map(buildSpellings),
  };
}

function buildSpellings(value: string) {
  const transliterated = NON_ASCII_REGEX.test(value)
    ? normalizeWords(value.replace(CYRILLIC_REGEX, (char) => CYRILLIC_TO_LATIN[char]))
    : undefined;

  return transliterated && transliterated !== value ? [value, transliterated] : [value];
}

function normalizeIdentifier(value: string) {
  return foldValue(value).trim();
}

function normalizeWords(value: string) {
  return foldValue(value).split(NON_WORD_REGEX).filter(Boolean).join(' ');
}

function foldValue(value: string) {
  return value.normalize('NFKD').replace(COMBINING_MARK_REGEX, '').normalize('NFC').toLowerCase();
}
