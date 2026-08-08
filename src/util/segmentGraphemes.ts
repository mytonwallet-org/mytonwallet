import { logDebugError } from './logs';

const SEGMENTER = typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function'
  ? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
  : undefined;

/** Splits text into user-perceived characters, keeping emoji sequences and combining marks intact */
export default function segmentGraphemes(text: string) {
  if (SEGMENTER) {
    try {
      return Array.from(SEGMENTER.segment(text), ({ segment }) => segment);
    } catch (err: any) {
      logDebugError('segmentGraphemes', err);
    }
  }

  return Array.from(text);
}
