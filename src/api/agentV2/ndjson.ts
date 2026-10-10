import type { AgentStreamEventV2 } from './protocol/types';

import { logDebug } from '../../util/logs';
import { decodeAgentV2StreamFrame } from './protocol/transportContracts';

const MAX_LINE_BYTES = 128 * 1024;
const MAX_REPLAY_LINES = 256;
const MAX_REPLAY_BYTES = 1024 * 1024;

export class AgentV2StreamProtocolError extends Error {
  constructor(message: string, readonly retryable = false) {
    super(message);
    this.name = 'AgentV2StreamProtocolError';
  }
}

export class AgentV2StreamTransportError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'AgentV2StreamTransportError';
  }
}

// A journaled tool call that this client cannot run
export interface AgentV2UnsupportedToolCall {
  type: 'unsupported_tool_call';
  protocolVersion: 3;
  runId: string;
  sequence: number;
  toolCall: { id: string; name: string };
}

export type AgentV2StreamItem = AgentStreamEventV2 | AgentV2UnsupportedToolCall;

export interface AgentV2StreamBinding {
  clientRunId: string;
  runId?: string;
  lastSequence: number;
  rawBySequence: Map<number, string>;
  rawBytes?: number;
  incompleteMessageIds?: Set<string>;
  ignoredTableIds?: Set<string>;
  text?: { messageId: string; anchor: number; value: string; isSealed: boolean };
}

export async function* parseAgentV2Ndjson(
  body: ReadableStream<Uint8Array>,
  binding: AgentV2StreamBinding,
): AsyncGenerator<AgentV2StreamItem> {
  const reader = body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let buffered = '';
  let bufferedBytes = 0;

  try {
    while (true) {
      let result: ReadableStreamReadResult<Uint8Array>;
      try {
        result = await reader.read();
      } catch (error) {
        throw new AgentV2StreamTransportError('Agent V2 stream read failed', { cause: error });
      }
      const { value, done } = result;
      if (done) break;
      bufferedBytes += value.byteLength;
      if (bufferedBytes > MAX_LINE_BYTES && !value.includes(10)) {
        throw new AgentV2StreamProtocolError('Agent V2 stream line is too large');
      }
      try {
        buffered += decoder.decode(value, { stream: true });
      } catch {
        throw new AgentV2StreamProtocolError('Agent V2 stream contains invalid UTF-8');
      }

      let newline = buffered.indexOf('\n');
      while (newline >= 0) {
        const line = buffered.slice(0, newline).replace(/\r$/u, '');
        buffered = buffered.slice(newline + 1);
        bufferedBytes = new TextEncoder().encode(buffered).byteLength;
        if (new TextEncoder().encode(line).byteLength > MAX_LINE_BYTES) {
          throw new AgentV2StreamProtocolError('Agent V2 stream line is too large');
        }
        if (line.length) {
          const accepted = acceptLine(line, binding);
          if (accepted) {
            yield accepted.event;
            accepted.commit();
          }
        }
        newline = buffered.indexOf('\n');
      }
    }

    try {
      buffered += decoder.decode();
    } catch {
      throw new AgentV2StreamProtocolError('Agent V2 stream contains invalid UTF-8');
    }
    if (buffered.length) {
      if (new TextEncoder().encode(buffered).byteLength > MAX_LINE_BYTES) {
        throw new AgentV2StreamProtocolError('Agent V2 stream line is too large');
      }
      const accepted = acceptLine(buffered.replace(/\r$/u, ''), binding);
      if (accepted) {
        yield accepted.event;
        accepted.commit();
      }
    }
  } finally {
    reader.releaseLock();
  }
}

interface AcceptedLine {
  event: AgentV2StreamItem;
  commit: () => void;
}

function acceptLine(line: string, binding: AgentV2StreamBinding): AcceptedLine | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line);
  } catch {
    throw new AgentV2StreamProtocolError('Agent V2 stream contains malformed JSON');
  }
  const frame = decodeAgentV2StreamFrame(parsed);
  const envelope = frame.disposition === 'handle' ? frame.event : frame.envelope;
  if (frame.disposition === 'handle' && frame.event.type === 'text_draft') {
    const draft = frame.event;
    if (draft.runId !== binding.runId) {
      throw new AgentV2StreamProtocolError('Agent V2 draft run binding changed');
    }
    const text = binding.text;
    if (!text || text.isSealed || text.messageId !== draft.messageId || text.anchor !== draft.sequence) {
      return undefined;
    }
    return acceptText(draft, binding, () => undefined);
  }
  const isActivity = frame.disposition === 'handle' ? frame.event.type === 'run_activity'
    : frame.disposition === 'ignore' && frame.wireType === 'run_activity';
  if (isActivity && 'ephemeral' in envelope && envelope.ephemeral === true) {
    if (!binding.runId || envelope.runId !== binding.runId) {
      throw new AgentV2StreamProtocolError('Agent V2 activity run binding changed');
    }
    if (envelope.sequence > binding.lastSequence) {
      throw new AgentV2StreamProtocolError('Agent V2 activity precedes its journal anchor', true);
    }
    if (envelope.sequence < binding.lastSequence || frame.disposition !== 'handle') return undefined;
    return { event: frame.event, commit: () => undefined };
  }
  const previous = binding.rawBySequence.get(envelope.sequence);

  if (envelope.sequence <= binding.lastSequence) {
    if (previous === line) return undefined;
    throw new AgentV2StreamProtocolError('Agent V2 stream contains a conflicting duplicate');
  }
  if (envelope.sequence !== binding.lastSequence + 1) {
    throw new AgentV2StreamProtocolError('Agent V2 stream contains a sequence gap', true);
  }
  if (previous !== undefined && previous !== line) {
    throw new AgentV2StreamProtocolError('Agent V2 stream contains a conflicting duplicate');
  }
  if (binding.runId && envelope.runId !== binding.runId) {
    throw new AgentV2StreamProtocolError('Agent V2 stream run binding changed');
  }

  if (frame.disposition === 'handle' && frame.event.type === 'run_start') {
    if (frame.event.clientRunId !== binding.clientRunId) {
      throw new AgentV2StreamProtocolError('Agent V2 stream client run binding changed');
    }
    binding.runId = frame.event.runId;
  } else if (!binding.runId) {
    throw new AgentV2StreamProtocolError('Agent V2 stream did not start with run_start');
  }

  rememberRawLine(binding, envelope.sequence, line);
  if (frame.disposition === 'handle' && frame.event.type === 'message_start') {
    binding.ignoredTableIds = undefined;
  }
  if (frame.disposition === 'handle' && frame.event.type === 'table_reference'
    && binding.ignoredTableIds?.has(frame.event.reference.tableId)) {
    binding.lastSequence = envelope.sequence;
    return undefined;
  }
  if (frame.disposition === 'ignore') {
    if (frame.ignoredTableId) {
      binding.ignoredTableIds ??= new Set();
      binding.ignoredTableIds.add(frame.ignoredTableId);
    }
    if (frame.incompleteMessageId) {
      binding.incompleteMessageIds ??= new Set();
      binding.incompleteMessageIds.add(frame.incompleteMessageId);
    }
    logDebug('AgentV2 optional event', { operation: 'stream', category: 'ignored',
      format: frame.wireType, boundary: frame.boundary });
    binding.lastSequence = envelope.sequence;
    return undefined;
  }
  if (frame.disposition === 'unsupportedTool') {
    const { runId, sequence } = envelope;
    return {
      event: { type: 'unsupported_tool_call', protocolVersion: 3, runId, sequence, toolCall: frame.toolCall },
      commit: () => {
        binding.lastSequence = sequence;
      },
    };
  }
  const commit = () => {
    binding.lastSequence = envelope.sequence;
    if (frame.event.type === 'message_start') {
      binding.text = { messageId: frame.event.messageId, anchor: envelope.sequence, value: '', isSealed: false };
    } else if ((frame.event.type === 'message_content_end' || frame.event.type === 'message_end') && binding.text) {
      binding.text.isSealed = true;
    }
  };
  if (frame.event.type === 'text_delta' && frame.event.offset !== undefined) {
    return acceptText(frame.event, binding, commit);
  }
  return { event: frame.event, commit };
}

function acceptText(
  event: Extract<AgentStreamEventV2, { type: 'text_delta' | 'text_draft' }>,
  binding: AgentV2StreamBinding,
  commitSequence: () => void,
): AcceptedLine | undefined {
  const text = binding.text;
  const offset = event.offset!;
  if (!text || text.messageId !== event.messageId || offset > text.value.length) {
    if (event.type === 'text_draft') return undefined;
    throw new AgentV2StreamProtocolError('Agent V2 text contains an offset gap', true);
  }
  const overlap = Math.min(event.delta.length, text.value.length - offset);
  if (text.value.slice(offset, offset + overlap) !== event.delta.slice(0, overlap)) {
    throw new AgentV2StreamProtocolError('Agent V2 text contains conflicting overlap');
  }
  const delta = event.delta.slice(overlap);
  if (text.value.length + delta.length > 200000) {
    throw new AgentV2StreamProtocolError('Agent V2 text exceeds the message limit');
  }
  if (!delta) {
    commitSequence();
    return undefined;
  }
  return {
    event: { ...event, type: 'text_delta', offset: text.value.length, delta },
    commit: () => {
      text.value += delta;
      commitSequence();
    },
  };
}

function rememberRawLine(binding: AgentV2StreamBinding, sequence: number, line: string) {
  const encoder = new TextEncoder();
  binding.rawBytes ??= [...binding.rawBySequence.values()].reduce(
    (total, value) => total + encoder.encode(value).byteLength,
    0,
  );
  const previous = binding.rawBySequence.get(sequence);
  if (previous !== undefined) binding.rawBytes -= encoder.encode(previous).byteLength;
  binding.rawBySequence.delete(sequence);
  binding.rawBySequence.set(sequence, line);
  binding.rawBytes += encoder.encode(line).byteLength;
  while (binding.rawBySequence.size > MAX_REPLAY_LINES || binding.rawBytes > MAX_REPLAY_BYTES) {
    const oldestSequence = binding.rawBySequence.keys().next().value;
    if (oldestSequence === undefined) break;
    const oldest = binding.rawBySequence.get(oldestSequence)!;
    binding.rawBySequence.delete(oldestSequence);
    binding.rawBytes -= encoder.encode(oldest).byteLength;
  }
}
