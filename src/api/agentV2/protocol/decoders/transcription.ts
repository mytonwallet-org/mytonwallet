import type { AgentTranscriptionResponseV2 } from '../types';

import { boundedString, fail, object, oneOf } from '../wireReader';
import { protocol } from './readers';

const TRANSCRIPTION_OUTCOMES: ReadonlySet<string> = new Set<AgentTranscriptionResponseV2['outcome']>([
  'transcribed',
  'no_speech',
]);
// The bound the public schema puts on a transcript, the same as on the text of a run request
const MAX_TRANSCRIPT_LENGTH = 20_000;

export function decodeAgentV2Transcription(value: unknown): AgentTranscriptionResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  const outcome = oneOf<AgentTranscriptionResponseV2['outcome']>(result.outcome, TRANSCRIPTION_OUTCOMES, '$.outcome');
  if (outcome === 'no_speech') return { protocolVersion: 3, outcome };
  const text = boundedString(result.text, '$.text', 1, MAX_TRANSCRIPT_LENGTH);
  if (!text.trim()) fail('$.text');
  return { protocolVersion: 3, outcome, text };
}
