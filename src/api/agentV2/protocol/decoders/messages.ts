import type {
  AgentDefaultThreadResponseV2,
  AgentErrorCodeV2,
  AgentHintsResponseV2,
  AgentMessageErrorV2,
  AgentPersistedMessageV2,
  AgentProblemReportResponseV2,
  AgentStarterHintV2,
  AgentThreadClearResponseV2,
  AgentThreadMessagesPageV2,
  AgentThreadSummaryV2,
} from '../types';
import type {
  JsonObject,
} from '../wireReader';

import {
  AgentV2CompatibilityError,
  AgentV2ContractError,
  array,
  boolean,
  boundedString,
  extensibleOneOf,
  fail,
  filterUnsupportedItems,
  integer,
  literal,
  object,
  oneOf,
  string,
  timestamp,
} from '../wireReader';
import {
  persistedAction,
} from './actions';
import { decodeMessageLinks } from './answerLinks';
import { decodeMessageTables } from './answerTables';
import {
  ERROR_CODES,
  followupUuid,
  protocol,
  uuid,
  validateEnumArray,
  validateErrorTiming,
} from './readers';
import {
  semanticContent,
} from './semantic';

const CURSOR_PATTERN = /^[A-Za-z0-9_-]{1,512}$/;
const FOLLOWUP_MARKDOWN_PATTERN = /(?:[*_~`]|\[[^\]]*\]\(|<\/?[A-Za-z]|^\s{0,3}(?:#{1,6}|>|[-+*]|\d+[.)])\s)/mu;
const RESPONSE_LANGUAGE_PATTERN = /^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$/u;

export interface AgentV2IncompatiblePersistedMessage {
  index: number;
  category: 'contract' | 'compatibility';
  boundary: string;
  messageId?: string;
}

export interface AgentV2DecodedMessagesPage extends AgentThreadMessagesPageV2 {
  incompatibleMessages?: AgentV2IncompatiblePersistedMessage[];
}

function cursor(value: unknown, path: string): string {
  const result = string(value, path);
  if (!CURSOR_PATTERN.test(result)) fail(path);
  return result;
}

export function threadSummary(value: unknown, path: string): AgentThreadSummaryV2 {
  const result = object(value, path);
  const id = uuid(result.id, `${path}.id`);
  const revision = integer(result.revision, `${path}.revision`, 1);
  const createdAt = timestamp(result.createdAt, `${path}.createdAt`);
  const updatedAt = timestamp(result.updatedAt, `${path}.updatedAt`);
  const lastActivityAt = timestamp(result.lastActivityAt, `${path}.lastActivityAt`);
  const clearedAt = result.clearedAt === undefined
    ? undefined
    : timestamp(result.clearedAt, `${path}.clearedAt`);
  const messageCount = integer(result.messageCount, `${path}.messageCount`);

  return {
    id,
    revision,
    createdAt,
    updatedAt,
    lastActivityAt,
    ...(clearedAt !== undefined && { clearedAt }),
    messageCount,
  };
}

export function followup(value: unknown, path: string) {
  const result = object(value, path);
  extensibleOneOf(result.kind, new Set(['suggested_prompt']), `${path}.kind`);
  followupUuid(result.id, `${path}.id`);
  followupText(result.text, `${path}.text`, 80);
}

function followupText(value: unknown, path: string, maxLength: number) {
  const result = boundedString(value, path, 1, maxLength);
  if (result.trim() !== result || /\p{Cc}/u.test(result) || FOLLOWUP_MARKDOWN_PATTERN.test(result)) fail(path);
}

export function filterFollowups(value: unknown, path: string, minLength = 0) {
  const items = array(value, path);
  if (items.length < minLength) fail(path);
  const result: unknown[] = [];
  const ids = new Set<string>();
  for (const [index, item] of items.entries()) {
    try {
      followup(item, `${path}[${index}]`);
      const id = (item as JsonObject).id as string;
      if (!ids.has(id)) {
        ids.add(id);
        result.push(item);
      }
    } catch (error) {
      if (error instanceof AgentV2CompatibilityError || error instanceof AgentV2ContractError) continue;
      throw error;
    }
    if (result.length === 3) break;
  }
  return result;
}

function persistedMessage(
  value: unknown, path: string, onInvalid: (error: AgentV2ContractError) => void,
): AgentPersistedMessageV2 {
  const result = object(value, path);
  validatePersistedMessage(result, path, onInvalid);
  return result;
}

function validatePersistedMessage(
  result: JsonObject,
  path: string,
  onInvalid: (error: AgentV2ContractError) => void,
): asserts result is JsonObject & AgentPersistedMessageV2 {
  uuid(result.id, `${path}.id`);
  uuid(result.threadId, `${path}.threadId`);
  oneOf(result.role, new Set(['user', 'assistant']), `${path}.role`);
  oneOf(result.status, new Set(['complete', 'error', 'cancelled']), `${path}.status`);
  if (result.content !== undefined) {
    const content = object(result.content, `${path}.content`);
    const kind = oneOf(content.kind, new Set(['markdown', 'semantic']), `${path}.content.kind`);
    if (kind === 'markdown') {
      if (typeof content.text !== 'string') fail(`${path}.content.text`);
      try {
        decodeMessageTables(content, `${path}.content`, onInvalid);
      } catch (error) {
        if (!(error instanceof AgentV2ContractError) && !(error instanceof AgentV2CompatibilityError)) throw error;
        delete content.tables;
        delete content.tableReferences;
        if (error instanceof AgentV2ContractError) onInvalid(error);
      }
      // A link never fails the message: one that cannot be placed is dropped and its label stays text
      try {
        decodeMessageLinks(content, `${path}.content`);
      } catch (error) {
        if (!(error instanceof AgentV2ContractError)) throw error;
        delete content.links;
      }
    } else {
      content.content = semanticContent(content.content, `${path}.content.content`);
    }
  }
  timestamp(result.createdAt, `${path}.createdAt`);
  if (result.runId !== undefined) uuid(result.runId, `${path}.runId`);
  if (result.responseLanguage !== undefined) {
    const language = decodeResponseLanguage(result.responseLanguage);
    if (language) result.responseLanguage = language;
    else delete result.responseLanguage;
  }
  if (result.actions !== undefined) {
    const actions = readOptionalItems(() => (
      filterUnsupportedItems(result.actions, `${path}.actions`, 8, persistedAction, 0, onInvalid)
    ), onInvalid);
    if (actions.length) result.actions = actions;
    else delete result.actions;
  }
  if (result.followups !== undefined) {
    const followups = readOptionalItems(() => filterFollowups(result.followups, `${path}.followups`));
    if (followups.length) result.followups = followups;
    else delete result.followups;
  }
  if (result.chains !== undefined) {
    try {
      validateEnumArray(result.chains, `${path}.chains`, 16, ['ton', 'tron']);
    } catch (error) {
      if (!(error instanceof AgentV2ContractError)) throw error;
      delete result.chains;
    }
  }
  if (result.error !== undefined) result.error = messageError(result.error, `${path}.error`);
}

export function decodeResponseLanguage(value: unknown): string | undefined {
  return typeof value === 'string'
    && value.length <= 35
    && RESPONSE_LANGUAGE_PATTERN.test(value)
    ? value
    : undefined;
}

function messageError(value: unknown, path: string): AgentMessageErrorV2 {
  const result = object(value, path);
  const retryable = boolean(result.retryable, `${path}.retryable`);
  const wireCode = boundedString(result.code, `${path}.code`, 1, 128);
  if (!ERROR_CODES.has(wireCode)) {
    return {
      code: retryable ? 'internal_error' : 'invalid_event',
      retryable,
    };
  }
  const code = oneOf<AgentErrorCodeV2>(wireCode, ERROR_CODES, `${path}.code`);
  if (result.retryAfterMs !== undefined) integer(result.retryAfterMs, `${path}.retryAfterMs`, 1);
  if (result.resetAt !== undefined) timestamp(result.resetAt, `${path}.resetAt`);
  validateErrorTiming(code, result, path);
  return {
    ...result,
    code,
    retryable,
  };
}

export function decodeAgentV2Hints(value: unknown): AgentHintsResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  literal(result.catalogVersion, 'agent-starter-hints-v1', '$.catalogVersion');
  const supportedHintIds = new Set<AgentStarterHintV2['id']>([
    'agent.capabilities', 'learn.swap', 'learn.staking', 'learn.security', 'receive.tokens',
  ]);
  const items = array(result.items, '$.items', 6).flatMap((item, index): AgentStarterHintV2[] => {
    const hint = object(item, `$.items[${index}]`);
    const rawId = boundedString(hint.id, `$.items[${index}].id`, 1, 80);
    if (!supportedHintIds.has(rawId as AgentStarterHintV2['id'])) return [];
    const id = oneOf<AgentStarterHintV2['id']>(rawId, supportedHintIds, `$.items[${index}].id`);
    let requiredCapabilities: AgentStarterHintV2['requiredCapabilities'];
    if (hint.requiredCapabilities !== undefined) {
      validateEnumArray(
        hint.requiredCapabilities,
        `$.items[${index}].requiredCapabilities`,
        2,
        ['wallet_read', 'receive_action'],
      );
      requiredCapabilities = array(hint.requiredCapabilities, `$.items[${index}].requiredCapabilities`)
        .map((capability) => oneOf<'wallet_read' | 'receive_action'>(
          capability,
          new Set(['wallet_read', 'receive_action']),
          `$.items[${index}].requiredCapabilities`,
        ));
    }
    return [{ id, ...(requiredCapabilities !== undefined && { requiredCapabilities }) }];
  });
  return {
    protocolVersion: 3,
    catalogVersion: 'agent-starter-hints-v1',
    items,
  };
}

export function decodeAgentV2DefaultThread(value: unknown): AgentDefaultThreadResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  return {
    protocolVersion: 3,
    thread: threadSummary(result.thread, '$.thread'),
    created: boolean(result.created, '$.created'),
  };
}

export function decodeAgentV2Messages(value: unknown): AgentV2DecodedMessagesPage {
  const result = object(value, '$');
  protocol(result, '$');
  const thread = threadSummary(result.thread, '$.thread');
  const messages: AgentPersistedMessageV2[] = [];
  const incompatibleMessages: AgentV2IncompatiblePersistedMessage[] = [];
  array(result.messages, '$.messages', 100).forEach((item, index) => {
    try {
      const issues: AgentV2ContractError[] = [];
      const message = persistedMessage(item, `$.messages[${index}]`, (error) => issues.push(error));
      if (issues.length) {
        message.error ??= { code: 'invalid_event', retryable: false };
        issues.forEach((error) => incompatibleMessages.push(incompatiblePersistedMessage(error, item, index)!));
      }
      messages.push(message);
    } catch (error) {
      const diagnostic = incompatiblePersistedMessage(error, item, index);
      if (!diagnostic) throw error;
      incompatibleMessages.push(diagnostic);
    }
  });
  const nextCursor = result.nextCursor === undefined ? undefined : cursor(result.nextCursor, '$.nextCursor');
  return {
    protocolVersion: 3,
    thread,
    messages,
    ...(nextCursor !== undefined && { nextCursor }),
    ...(incompatibleMessages.length && { incompatibleMessages }),
  };
}

function incompatiblePersistedMessage(
  error: unknown,
  value: unknown,
  index: number,
): AgentV2IncompatiblePersistedMessage | undefined {
  const messageId = persistedMessageId(value);
  if (error instanceof AgentV2ContractError) {
    return {
      index,
      category: 'contract',
      boundary: error.path,
      ...(messageId && { messageId }),
    };
  }
  if (error instanceof AgentV2CompatibilityError) {
    return {
      index,
      category: 'compatibility',
      boundary: error.boundary,
      ...(messageId && { messageId }),
    };
  }
  return undefined;
}

function persistedMessageId(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  try {
    return uuid((value as JsonObject).id, '$.id');
  } catch {
    return undefined;
  }
}

export function decodeAgentV2ThreadClear(value: unknown): AgentThreadClearResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  return {
    protocolVersion: 3,
    thread: threadSummary(result.thread, '$.thread'),
    duplicate: boolean(result.duplicate, '$.duplicate'),
  };
}

export function decodeAgentV2ProblemReport(value: unknown): AgentProblemReportResponseV2 {
  const result = object(value, '$');
  protocol(result, '$');
  return {
    protocolVersion: 3,
    reportId: uuid(result.reportId, '$.reportId'),
    duplicate: boolean(result.duplicate, '$.duplicate'),
  };
}

function readOptionalItems(read: () => unknown[], onInvalid?: (error: AgentV2ContractError) => void): unknown[] {
  try {
    return read();
  } catch (error) {
    if (!(error instanceof AgentV2ContractError) && !(error instanceof AgentV2CompatibilityError)) throw error;
    if (error instanceof AgentV2ContractError) onInvalid?.(error);
    return [];
  }
}
