import type {
  AgentErrorCodeV2,
  AgentStreamEventV2,
} from '../types';
import type { JsonObject } from '../wireReader';

import { AGENT_EVENT_TYPES, AGENT_RUN_ACTIVITY_CODES } from '../../generated/constants';
import { AGENT_V2_TOOL_CONTRACTS } from '../toolContractCatalog';
import {
  AgentV2CompatibilityError,
  AgentV2ContractError,
  array,
  boolean,
  boundedString,
  fail,
  integer,
  literal,
  object,
  oneOf,
  string,
  timestamp,
} from '../wireReader';
import {
  action,
} from './actions';
import { decodeAnswerLink } from './answerLinks';
import { decodeAnswerTable, decodeAnswerTableReference } from './answerTables';
import {
  decodeResponseLanguage,
  filterFollowups,
  followup,
  threadSummary,
} from './messages';
import {
  ERROR_CODES,
  protocol,
  uuid,
} from './readers';
import {
  semanticContent,
} from './semantic';
import {
  toolCall,
} from './wallet';

const EVENT_TYPES: ReadonlySet<string> = new Set(AGENT_EVENT_TYPES);

const MESSAGE_EXTENSION_EVENTS = new Set([
  'action', 'table_data', 'table_reference', 'semantic_content', 'followups',
]);
// A malformed link, its message binding included, is dropped; its label stays text and the message completes
const OPTIONAL_EVENTS = new Set([...MESSAGE_EXTENSION_EVENTS, 'run_activity', 'text_link']);
const CONTENT_EVENTS = new Set(['action', 'table_data', 'table_reference', 'semantic_content']);

const TOOL_STATUSES = new Set(['complete', 'failed', 'timeout', 'rejected', 'cancelled']);

const RUN_ACTIVITY_CODES: ReadonlySet<string> = new Set(AGENT_RUN_ACTIVITY_CODES);

const RUN_ACTIVITY_STATUSES = new Set(['active', 'completed']);

const FINISH_REASONS = new Set(['complete', 'cancelled', 'tool_unavailable', 'run_interrupted']);

export interface AgentV2StreamEnvelope {
  ephemeral?: true;
  protocolVersion: 3;
  runId: string;
  sequence: number;
  createdAt?: string;
}

export type AgentV2StreamFrame = {
  disposition: 'handle';
  event: AgentStreamEventV2;
} | {
  disposition: 'ignore';
  envelope: AgentV2StreamEnvelope;
  wireType: string;
  incompleteMessageId?: string;
  ignoredTableId?: string;
  boundary?: string;
} | {
  disposition: 'unsupportedTool';
  envelope: AgentV2StreamEnvelope;
  toolCall: { id: string; name: string };
};

export function decodeAgentV2StreamFrame(value: unknown): AgentV2StreamFrame {
  const result = object(value, '$');
  const envelope = readStreamEnvelope(result);
  const wireType = boundedString(result.type, '$.type', 1, 64);
  if (!EVENT_TYPES.has(wireType)) return { disposition: 'ignore', envelope, wireType };
  if (wireType === 'tool_call') {
    const toolCall = readUnsupportedToolCall(result.toolCall);
    if (toolCall) return { disposition: 'unsupportedTool', envelope, toolCall };
  }

  const normalized = { ...result };
  if (MESSAGE_EXTENSION_EVENTS.has(wireType)) {
    uuid(result.messageId, '$.messageId');
  }
  try {
    if (wireType === 'tool_status') {
      uuid(result.toolCallId, '$.toolCallId');
      const status = boundedString(result.status, '$.status', 1, 64);
      if (!TOOL_STATUSES.has(status)) return { disposition: 'ignore', envelope, wireType };
    } else if (wireType === 'run_activity') {
      const code = boundedString(result.code, '$.code', 1, 64);
      const status = boundedString(result.status, '$.status', 1, 64);
      if (!RUN_ACTIVITY_CODES.has(code) || !RUN_ACTIVITY_STATUSES.has(status)) {
        return { disposition: 'ignore', envelope, wireType };
      }
    } else if (wireType === 'followups') {
      uuid(result.messageId, '$.messageId');
      normalized.items = filterFollowups(result.items, '$.items', 1);
      if (!(normalized.items as unknown[]).length) return { disposition: 'ignore', envelope, wireType };
    } else if (wireType === 'message_end') {
      const finishReason = boundedString(result.finishReason, '$.finishReason', 1, 64);
      if (!FINISH_REASONS.has(finishReason)) {
        normalized.finishReason = 'run_interrupted';
      }
    } else if (wireType === 'error') {
      const retryable = boolean(result.retryable, '$.retryable');
      const code = boundedString(result.code, '$.code', 1, 128);
      if (!ERROR_CODES.has(code)) {
        normalized.code = retryable ? 'internal_error' : 'invalid_event';
        delete normalized.retryAfterMs;
        delete normalized.resetAt;
      }
    }

    return { disposition: 'handle', event: decodeAgentV2StreamEvent(normalized) };
  } catch (error) {
    if (OPTIONAL_EVENTS.has(wireType)
      && (error instanceof AgentV2ContractError || error instanceof AgentV2CompatibilityError)) {
      const isContentInvalid = CONTENT_EVENTS.has(wireType)
        && error instanceof AgentV2ContractError;
      return { disposition: 'ignore', envelope, wireType,
        ...(isContentInvalid ? { incompleteMessageId: result.messageId as string } : {}),
        ...(wireType === 'table_data' && result.table && typeof result.table === 'object'
          && typeof (result.table as JsonObject).id === 'string'
          ? { ignoredTableId: (result.table as JsonObject).id as string } : {}),
        boundary: error instanceof AgentV2ContractError ? error.path : error.boundary };
    }
    throw error;
  }
}

// The server waits for a result of every tool call, so a call this client cannot run is answered with a rejection
function readUnsupportedToolCall(value: unknown) {
  const toolCall = object(value, '$.toolCall');
  const id = uuid(toolCall.id, '$.toolCall.id');
  const name = boundedString(toolCall.name, '$.toolCall.name', 1, 64);
  return AGENT_V2_TOOL_CONTRACTS.some((contract) => contract.name === name) ? undefined : { id, name };
}

function readStreamEnvelope(result: JsonObject): AgentV2StreamEnvelope {
  protocol(result, '$');
  const runId = uuid(result.runId, '$.runId');
  const sequence = integer(result.sequence, '$.sequence', 1);
  const createdAt = result.createdAt === undefined ? undefined : timestamp(result.createdAt, '$.createdAt');
  return {
    ...(result.type === 'run_activity' && result.ephemeral === true && { ephemeral: true as const }),
    protocolVersion: 3,
    runId,
    sequence,
    ...(createdAt !== undefined && { createdAt }),
  };
}

export function decodeAgentV2StreamEvent(value: unknown): AgentStreamEventV2 {
  const result = object(value, '$');
  validateAgentV2StreamEvent(result);
  return result;
}

function validateAgentV2StreamEvent(
  result: JsonObject,
): asserts result is JsonObject & AgentStreamEventV2 {
  if (result.protocolVersion !== 3) {
    throw new AgentV2CompatibilityError(
      '$.protocolVersion',
      undefined,
      typeof result.protocolVersion === 'number' ? result.protocolVersion : undefined,
    );
  }
  if (typeof result.type !== 'string' || !EVENT_TYPES.has(result.type)) {
    throw new AgentV2CompatibilityError(
      '$.type',
      typeof result.type === 'string' ? result.type.slice(0, 64) : undefined,
      2,
    );
  }
  const type = result.type;
  uuid(result.runId, '$.runId');
  const sequence = integer(result.sequence, '$.sequence', 1);
  if (result.createdAt !== undefined) timestamp(result.createdAt, '$.createdAt');

  switch (type) {
    case 'run_start':
      literal(sequence, 1, '$.sequence');
      uuid(result.clientRunId, '$.clientRunId');
      uuid(result.threadId, '$.threadId');
      integer(result.threadRevision, '$.threadRevision', 1);
      break;
    case 'thread':
      threadSummary(result.thread, '$.thread');
      break;
    case 'message_start':
      uuid(result.messageId, '$.messageId');
      literal(result.role, 'assistant', '$.role');
      oneOf(result.contentKind, new Set(['markdown', 'semantic']), '$.contentKind');
      if (result.responseLanguage !== undefined) {
        const language = decodeResponseLanguage(result.responseLanguage);
        if (language) result.responseLanguage = language;
        else delete result.responseLanguage;
      }
      break;
    case 'table_data':
      uuid(result.messageId, '$.messageId');
      result.table = decodeAnswerTable(result.table, '$.table');
      break;
    case 'table_reference':
      uuid(result.messageId, '$.messageId');
      result.reference = decodeAnswerTableReference(result.reference, '$.reference');
      break;
    case 'text_link':
      uuid(result.messageId, '$.messageId');
      result.link = decodeAnswerLink(result.link, '$.link');
      break;
    case 'text_draft':
    case 'text_delta':
      uuid(result.messageId, '$.messageId');
      string(result.delta, '$.delta');
      if (result.type === 'text_draft' || result.offset !== undefined) {
        if (!Number.isSafeInteger(result.offset) || Number(result.offset) < 0 || Number(result.offset) > 200000) {
          fail('$.offset');
        }
      }
      break;
    case 'tool_call':
      toolCall(result.toolCall, '$.toolCall');
      break;
    case 'tool_status':
      uuid(result.toolCallId, '$.toolCallId');
      oneOf(result.status, TOOL_STATUSES, '$.status');
      break;
    case 'run_activity':
      if (result.ephemeral !== undefined) literal(result.ephemeral, true, '$.ephemeral');
      oneOf(result.code, RUN_ACTIVITY_CODES, '$.code');
      oneOf(result.status, RUN_ACTIVITY_STATUSES, '$.status');
      break;
    case 'action':
      uuid(result.messageId, '$.messageId');
      action(result.action, '$.action');
      break;
    case 'followups':
      uuid(result.messageId, '$.messageId');
      array(result.items, '$.items', 3).forEach((item, index) => followup(item, `$.items[${index}]`));
      break;
    case 'semantic_content':
      uuid(result.messageId, '$.messageId');
      result.content = semanticContent(result.content, '$.content');
      break;
    case 'message_content_end':
      uuid(result.messageId, '$.messageId');
      break;
    case 'message_end':
      uuid(result.messageId, '$.messageId');
      oneOf(result.finishReason, FINISH_REASONS, '$.finishReason');
      break;
    case 'error': {
      const code = oneOf<AgentErrorCodeV2>(result.code, ERROR_CODES, '$.code');
      boolean(result.retryable, '$.retryable');
      if (result.messageId !== undefined) uuid(result.messageId, '$.messageId');
      if (result.retryAfterMs !== undefined) integer(result.retryAfterMs, '$.retryAfterMs', 1);
      if (result.resetAt !== undefined) timestamp(result.resetAt, '$.resetAt');
      if ((result.retryAfterMs !== undefined || result.resetAt !== undefined)
        && code !== 'agent_capacity_exhausted'
        && code !== 'user_quota_exhausted') {
        fail('$.code');
      }
      break;
    }
    default:
      throw new AgentV2CompatibilityError('$.type', type, 2);
  }
}
