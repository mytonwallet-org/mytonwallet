import type {
  AgentToolCall,
  AgentToolResultAckV2,
  AgentWalletQueryCapabilityV1,
} from '../types';
import type {
  JsonObject,
} from '../wireReader';

import contractManifest from '../../generated/manifest.json';
import {
  AGENT_V2_TOOL_CONTRACTS,
} from '../toolContractCatalog';
import {
  array,
  boolean,
  boundedInteger,
  boundedString,
  fail,
  integer,
  literal,
  object,
  oneOf,
  optionalString,
  strictKeys,
  string,
  timestamp,
} from '../wireReader';
import {
  protocol,
  uuid,
  validateEnumArray,
} from './readers';

const FULL_TRANSACTION_HASH_PATTERN = /^(?:(?:0[xX])?[A-Fa-f0-9]{64}|[A-Za-z0-9+/_-]{43,126}={0,2})$/u;
const SHA256_PATTERN = /^[a-f0-9]{64}$/u;

const MIN_TOOL_TIMEOUT_MS = 100;

const MAX_TOOL_TIMEOUT_MS = 30_000;

// Both wallet tools may ask for results of up to 600 KiB, which fits a directory of accounts on every network
const MAX_TOOL_RESULT_BYTES = 614_400;

const MAX_CONTACT_PAGE_SIZE = 300;

const TOOL_NAMES = /* @__PURE__ */ new Set(/* @__PURE__ */ AGENT_V2_TOOL_CONTRACTS.map(({ name }) => name));

const TOOL_SCOPES = /* @__PURE__ */ Object.fromEntries(
  /* @__PURE__ */ AGENT_V2_TOOL_CONTRACTS.map(({ name, scopes }) => [name, scopes[0]]),
) as Record<AgentToolCall['name'], string>;

function walletSession(value: unknown, path: string) {
  const result = object(value, path);
  uuid(result.sessionId, `${path}.sessionId`);
  integer(result.revision, `${path}.revision`);
  oneOf(result.accountScope, new Set(['current', 'selected', 'explicitAll']), `${path}.accountScope`);
  string(result.activeAccountRef, `${path}.activeAccountRef`);
  optionalString(result.activeNetwork, `${path}.activeNetwork`);
}

function directorySession(value: unknown, path: string) {
  const result = object(value, path);
  strictKeys(result, path, ['sessionId', 'revision', 'activeAccountRef']);
  uuid(result.sessionId, `${path}.sessionId`);
  boundedInteger(result.revision, `${path}.revision`, 1, Number.MAX_SAFE_INTEGER);
  boundedString(result.activeAccountRef, `${path}.activeAccountRef`, 1, 128);
}

function directoryGrant(value: unknown, path: string) {
  const result = object(value, path);
  strictKeys(result, path, [
    'schemaVersion', 'kind', 'sourceCapabilityId', 'messageId', 'sessionId', 'revision',
  ]);
  literal(result.schemaVersion, 1, `${path}.schemaVersion`);
  literal(result.kind, 'send_wallet_resolution', `${path}.kind`);
  literal(result.sourceCapabilityId, 'wallet.send-prepare', `${path}.sourceCapabilityId`);
  uuid(result.messageId, `${path}.messageId`);
  uuid(result.sessionId, `${path}.sessionId`);
  boundedInteger(result.revision, `${path}.revision`, 1, Number.MAX_SAFE_INTEGER);
}

function validateToolArguments(tool: AgentToolCall, path: string) {
  const args = object(tool.arguments, `${path}.arguments`);

  switch (tool.name) {
    case 'wallet.data.query': {
      validateWalletDataQuery(args, `${path}.arguments`);
      break;
    }
    case 'wallet.directory.query': {
      strictKeys(args, `${path}.arguments`, ['schemaVersion', 'purpose']);
      literal(args.schemaVersion, 1, `${path}.arguments.schemaVersion`);
      literal(args.purpose, 'send_wallet_resolution', `${path}.arguments.purpose`);
      break;
    }
    default:
      fail(`${path}.name`);
  }
}

export function toolCall(value: unknown, path: string) {
  const result = object(value, path);
  uuid(result.id, `${path}.id`);
  const name = oneOf<AgentToolCall['name']>(result.name, TOOL_NAMES, `${path}.name`);
  if (result.maxResultBytes !== undefined) {
    boundedInteger(result.maxResultBytes, `${path}.maxResultBytes`, 1, MAX_TOOL_RESULT_BYTES);
  }
  const scopes = array(result.scopes, `${path}.scopes`);
  if (scopes.length !== 1 || scopes[0] !== TOOL_SCOPES[name]) fail(`${path}.scopes`);
  boundedInteger(result.timeoutMs, `${path}.timeoutMs`, MIN_TOOL_TIMEOUT_MS, MAX_TOOL_TIMEOUT_MS);
  validateIntentSource(result, path);
  validateScopeIntent(result, path);
  if (name === 'wallet.directory.query') {
    boundedInteger(result.maxResultBytes, `${path}.maxResultBytes`, 1, MAX_TOOL_RESULT_BYTES);
    directorySession(result.directorySession, `${path}.directorySession`);
    directoryGrant(result.directoryGrant, `${path}.directoryGrant`);
    if (result.walletContextSession !== undefined) fail(`${path}.walletContextSession`);
    if (result.scopeIntent !== undefined) fail(`${path}.scopeIntent`);
    const session = object(result.directorySession, `${path}.directorySession`);
    const grant = object(result.directoryGrant, `${path}.directoryGrant`);
    const source = object(result.intentSource, `${path}.intentSource`);
    if (source.kind !== 'userMessage'
      || source.messageId !== grant.messageId
      || session.sessionId !== grant.sessionId
      || session.revision !== grant.revision) fail(`${path}.directoryGrant`);
  } else {
    walletSession(result.walletContextSession, `${path}.walletContextSession`);
    if (result.directorySession !== undefined) fail(`${path}.directorySession`);
    if (result.directoryGrant !== undefined) fail(`${path}.directoryGrant`);
  }
}

export function decodeAgentV2ToolArguments(tool: AgentToolCall): AgentToolCall {
  validateToolArguments(tool, '$.toolCall');
  validateToolAccountScope(tool, '$.toolCall');
  return tool;
}

function validateWalletDataQuery(args: JsonObject, path: string) {
  const operation = oneOf(args.operation, new Set([
    'account.inventory', 'assets.search', 'positions.list', 'portfolio.aggregate',
    'transactions.list', 'transactions.detail', 'contacts.list', 'value.series',
  ]), `${path}.operation`);
  if (operation === 'assets.search') {
    strictKeys(args, path, ['operation', 'query', 'chains', 'pageSize']);
    boundedString(args.query, `${path}.query`, 1, 160);
    validateUniqueStringArray(args.chains, `${path}.chains`);
    boundedInteger(args.pageSize, `${path}.pageSize`, 1, 10);
    return;
  }

  validateWalletAccountSelector(args.accountSelector, `${path}.accountSelector`, true);
  if (operation === 'account.inventory') {
    strictKeys(args, path, [
      'operation', 'accountSelector', 'chains', 'includePublicAddressReason',
      'includePortfolioTotals',
    ]);
    validateUniqueStringArray(args.chains, `${path}.chains`);
    if (args.includePublicAddressReason !== undefined) {
      oneOf(args.includePublicAddressReason, new Set([
        'receive', 'wallet_location', 'prepare_validation', 'chain_lookup',
      ]), `${path}.includePublicAddressReason`);
    }
    if (args.includePortfolioTotals !== undefined) {
      literal(args.includePortfolioTotals, true, `${path}.includePortfolioTotals`);
    }
    if (args.includePublicAddressReason !== undefined && args.includePortfolioTotals !== undefined) {
      fail(path);
    }
    return;
  }
  if (operation === 'positions.list') {
    strictKeys(args, path, [
      'operation', 'accountSelector', 'chains', 'assetSelectors',
      'positionKinds', 'riskMode', 'visibilityMode', 'includeZero', 'sort', 'pageSize',
    ]);
    validateUniqueStringArray(args.chains, `${path}.chains`);
    const assets = array(args.assetSelectors, `${path}.assetSelectors`, 10);
    assets.forEach((item, index) => validateAssetSelector(item, `${path}.assetSelectors[${index}]`));
    validateRequiredEnumArray(args.positionKinds, `${path}.positionKinds`, 5, [
      'fungible', 'nft', 'staking', 'vesting', 'vault',
    ]);
    oneOf(args.riskMode, new Set(['exclude', 'only', 'all']), `${path}.riskMode`);
    oneOf(args.visibilityMode, new Set(['visible', 'hidden', 'all']), `${path}.visibilityMode`);
    boolean(args.includeZero, `${path}.includeZero`);
    oneOf(args.sort, new Set(['wallet_order', 'value_desc', 'quantity_desc']), `${path}.sort`);
    boundedInteger(args.pageSize, `${path}.pageSize`, 1, 100);
    return;
  }
  if (operation === 'portfolio.aggregate') {
    strictKeys(args, path, [
      'operation', 'accountSelector', 'accountFilter', 'chains', 'range', 'groupBy',
      'riskMode', 'visibilityMode', 'historySource',
    ]);
    if (args.historySource !== undefined) oneOf(args.historySource, new Set(['backend']), `${path}.historySource`);
    if (args.accountFilter !== undefined) {
      if (object(args.accountSelector, `${path}.accountSelector`).kind !== 'explicitAll') fail(path);
      const accountFilter = object(args.accountFilter, `${path}.accountFilter`);
      strictKeys(accountFilter, `${path}.accountFilter`, ['viewOnly']);
      oneOf(
        accountFilter.viewOnly,
        new Set(['include', 'exclude', 'only']),
        `${path}.accountFilter.viewOnly`,
      );
    }
    validateUniqueStringArray(args.chains, `${path}.chains`);
    validateHistoryRange(args.range, `${path}.range`);
    validateRequiredEnumArray(args.groupBy, `${path}.groupBy`, 4, [
      'account', 'asset', 'network', 'position_type',
    ]);
    oneOf(args.riskMode, new Set(['exclude', 'only', 'all']), `${path}.riskMode`);
    oneOf(args.visibilityMode, new Set(['visible', 'hidden', 'all']), `${path}.visibilityMode`);
    return;
  }
  if (operation === 'transactions.list') {
    strictKeys(args, path, [
      'operation', 'accountSelector', 'chains', 'filters', 'riskMode', 'pageSize',
    ]);
    validateUniqueStringArray(args.chains, `${path}.chains`);
    validateWalletFilterSet(args.filters, `${path}.filters`);
    oneOf(args.riskMode, new Set(['exclude', 'only', 'all']), `${path}.riskMode`);
    boundedInteger(args.pageSize, `${path}.pageSize`, 1, 50);
    return;
  }
  if (operation === 'transactions.detail') {
    strictKeys(args, path, ['operation', 'accountSelector', 'hash']);
    const hash = boundedString(args.hash, `${path}.hash`, 43, 128);
    if (!FULL_TRANSACTION_HASH_PATTERN.test(hash)) fail(`${path}.hash`);
    return;
  }
  if (operation === 'contacts.list') {
    strictKeys(args, path, [
      'operation', 'accountSelector', 'query', 'chains', 'ownWalletChains', 'pageSize', 'purpose',
    ]);
    if (!isWireNull(args.query)) boundedString(args.query, `${path}.query`, 1, 120);
    validateUniqueStringArray(args.chains, `${path}.chains`);
    validateUniqueStringArray(args.ownWalletChains, `${path}.ownWalletChains`);
    boundedInteger(args.pageSize, `${path}.pageSize`, 1, MAX_CONTACT_PAGE_SIZE);
    if (args.purpose !== undefined) {
      literal(args.purpose, 'send_recipient_resolution', `${path}.purpose`);
      literal(object(args.accountSelector, `${path}.accountSelector`).kind, 'current', `${path}.accountSelector.kind`);
      if (!isWireNull(args.query) || array(args.chains, `${path}.chains`).length) fail(path);
    }
    return;
  }
  strictKeys(args, path, [
    'operation', 'accountSelector', 'chains', 'metric', 'assetSelectors',
    'range', 'maxPoints',
  ]);
  validateUniqueStringArray(args.chains, `${path}.chains`);
  const metric = oneOf(args.metric, new Set(['portfolio_value', 'position_value']), `${path}.metric`);
  const assets = array(args.assetSelectors, `${path}.assetSelectors`, 5);
  if (metric === 'position_value' && !assets.length) fail(`${path}.assetSelectors`);
  assets.forEach((item, index) => validateAssetSelector(item, `${path}.assetSelectors[${index}]`));
  validateHistoryRange(args.range, `${path}.range`);
  boundedInteger(args.maxPoints, `${path}.maxPoints`, 1, 64);
}

function validateWalletFilterSet(value: unknown, path: string) {
  const filterSet = object(value, path);
  strictKeys(filterSet, path, ['schemaVersion', 'catalogDigest', 'clauses']);
  literal(filterSet.schemaVersion, 1, `${path}.schemaVersion`);
  const catalogDigest = boundedString(filterSet.catalogDigest, `${path}.catalogDigest`, 64, 64);
  if (!SHA256_PATTERN.test(catalogDigest)) fail(`${path}.catalogDigest`);
  literal(catalogDigest, contractManifest.walletFilterCatalogSha256, `${path}.catalogDigest`);
  const clauses = array(filterSet.clauses, `${path}.clauses`, 8);
  const fields = new Set<string>();
  clauses.forEach((value, index) => {
    const clausePath = `${path}.clauses[${index}]`;
    const clause = object(value, clausePath);
    const field = oneOf(clause.field, new Set([
      'transaction.status', 'transaction.direction', 'transaction.timestamp',
      'transaction.chain', 'transaction.asset',
    ]), `${clausePath}.field`);
    if (fields.has(field)) fail(`${clausePath}.field`);
    fields.add(field);
    if (field === 'transaction.timestamp') {
      strictKeys(clause, clausePath, ['field', 'operator', 'range']);
      literal(clause.operator, 'timestamp_range', `${clausePath}.operator`);
      const range = object(clause.range, `${clausePath}.range`);
      strictKeys(range, `${clausePath}.range`, [
        'rangeKind', 'fromInclusive', 'toExclusive', 'timeZone', 'resolvedAt',
      ]);
      oneOf(range.rangeKind, new Set([
        'today', 'yesterday', 'current_week', 'previous_week', 'current_month',
        'previous_month', 'rolling_days', 'rolling_weeks', 'rolling_months', 'absolute',
      ]), `${clausePath}.range.rangeKind`);
      const from = timestamp(range.fromInclusive, `${clausePath}.range.fromInclusive`);
      const to = timestamp(range.toExclusive, `${clausePath}.range.toExclusive`);
      if (Date.parse(from) >= Date.parse(to)) fail(`${clausePath}.range`);
      boundedString(range.timeZone, `${clausePath}.range.timeZone`, 1, 64);
      timestamp(range.resolvedAt, `${clausePath}.range.resolvedAt`);
    } else {
      strictKeys(clause, clausePath, ['field', 'operator', 'values']);
      if (field === 'transaction.asset') {
        literal(clause.operator, 'asset_matches_any', `${clausePath}.operator`);
        const selectors = array(clause.values, `${clausePath}.values`, 10);
        if (!selectors.length) fail(`${clausePath}.values`);
        selectors.forEach((selector, selectorIndex) => {
          validateAssetSelector(selector, `${clausePath}.values[${selectorIndex}]`);
        });
      } else {
        literal(clause.operator, 'in', `${clausePath}.operator`);
        const allowed = field === 'transaction.status'
          ? ['pending', 'pendingTrusted', 'confirmed', 'completed', 'failed', 'expired']
          : field === 'transaction.direction' ? ['incoming', 'outgoing', 'self'] : undefined;
        if (allowed) validateEnumArray(clause.values, `${clausePath}.values`, allowed.length, allowed);
        else validateUniqueStringArray(clause.values, `${clausePath}.values`);
        if (!array(clause.values, `${clausePath}.values`).length) fail(`${clausePath}.values`);
      }
    }
  });
}

function validateWalletAccountSelector(value: unknown, path: string, extended: boolean) {
  const selector = object(value, path);
  const selectorKind = oneOf(
    selector.kind,
    new Set(extended
      ? ['current', 'named', 'ordinal', 'explicitAll']
      : ['current', 'named', 'explicitAll']),
    `${path}.kind`,
  );
  strictKeys(selector, path, selectorKind === 'named' ? ['kind', 'label']
    : selectorKind === 'ordinal' ? ['kind', 'index']
      : ['kind']);
  if (selectorKind === 'named') boundedString(selector.label, `${path}.label`, 1, 80);
  if (selectorKind === 'ordinal') boundedInteger(selector.index, `${path}.index`, 1, 100);
  return selectorKind;
}

export function isWireNull(value: unknown): boolean {
  return typeof value === 'object' && !value;
}

function validateRequiredEnumArray(value: unknown, path: string, limit: number, allowed: string[]) {
  const items = array(value, path, limit);
  if (!items.length) fail(path);
  validateEnumArray(items, path, limit, allowed);
}

function validateHistoryRange(value: unknown, path: string) {
  oneOf(value, new Set(['1d', '7d', '1m', '3m', '1y', 'all']), path);
}

function validateIntentSource(tool: JsonObject, path: string) {
  if (tool.intentSource === undefined) return;
  const result = object(tool.intentSource, `${path}.intentSource`);
  strictKeys(result, `${path}.intentSource`, ['kind', 'messageId', 'followupId']);
  const kind = oneOf(
    result.kind,
    new Set(['userMessage', 'actionFollowup']),
    `${path}.intentSource.kind`,
  );
  uuid(result.messageId, `${path}.intentSource.messageId`);
  if (kind === 'actionFollowup') {
    boundedString(result.followupId, `${path}.intentSource.followupId`, 1, 128);
  } else if (result.followupId !== undefined) {
    fail(`${path}.intentSource.followupId`);
  }
}

function validateUniqueStringArray(value: unknown, path: string) {
  const items = array(value, path)
    .map((item, index) => boundedString(item, `${path}[${index}]`, 1, 32));
  if (new Set(items).size !== items.length) fail(path);
}

function validateAssetSelector(value: unknown, path: string) {
  const result = object(value, path);
  strictKeys(result, path, ['slug', 'chain', 'tokenAddress', 'symbol']);
  if (!Object.values(result).some((item) => item !== undefined)) fail(path);
  if (result.slug !== undefined) boundedString(result.slug, `${path}.slug`, 1, 128);
  if (result.chain !== undefined) boundedString(result.chain, `${path}.chain`, 1, 32);
  if (result.tokenAddress !== undefined) {
    boundedString(result.tokenAddress, `${path}.tokenAddress`, 1, 256);
  }
  if (result.symbol !== undefined) boundedString(result.symbol, `${path}.symbol`, 1, 32);
}

function validateScopeIntent(tool: JsonObject, path: string) {
  if (tool.scopeIntent === undefined) return;
  const result = object(tool.scopeIntent, `${path}.scopeIntent`);
  strictKeys(result, `${path}.scopeIntent`, ['messageId', 'reason']);
  uuid(result.messageId, `${path}.scopeIntent.messageId`);
  oneOf(
    result.reason,
    new Set([
      'explicit_all_wallet_query',
      'selected_wallet_query',
    ]),
    `${path}.scopeIntent.reason`,
  );
  const intentSource = tool.intentSource === undefined
    ? undefined
    : object(tool.intentSource, `${path}.intentSource`);
  if (
    !intentSource
    || intentSource.kind !== 'userMessage'
    || intentSource.messageId !== result.messageId
  ) {
    fail(`${path}.scopeIntent.messageId`);
  }
}

function validateToolAccountScope(tool: AgentToolCall, path: string) {
  if (tool.name === 'wallet.directory.query') return;
  const sessionScope = tool.walletContextSession.accountScope;
  const args = object(tool.arguments, `${path}.arguments`);
  if (tool.name === 'wallet.data.query') {
    if (args.operation === 'assets.search') {
      if (sessionScope !== 'current' || tool.scopeIntent !== undefined) {
        fail(`${path}.walletContextSession.accountScope`);
      }
      return;
    }
    const selector = object(args.accountSelector, `${path}.arguments.accountSelector`);
    const expected = selector.kind === 'explicitAll'
      ? 'explicitAll'
      : ['named', 'ordinal'].includes(String(selector.kind)) ? 'selected' : 'current';
    if (sessionScope !== expected) fail(`${path}.walletContextSession.accountScope`);
    if (sessionScope === 'explicitAll') {
      if (tool.scopeIntent?.reason !== 'explicit_all_wallet_query') fail(`${path}.scopeIntent`);
    } else if (sessionScope === 'selected') {
      if (tool.scopeIntent?.reason !== 'selected_wallet_query') fail(`${path}.scopeIntent`);
    } else if (tool.scopeIntent !== undefined) {
      fail(`${path}.scopeIntent`);
    }
    return;
  }
}

/** The wallet-query feature of /capabilities: its status and, when available, the filter catalog it reads */
export function walletQueryCapability(value: unknown, path: string): AgentWalletQueryCapabilityV1 {
  const result = object(value, path);
  const status = oneOf<'available' | 'disabled'>(result.status, new Set(['available', 'disabled']), `${path}.status`);
  if (status === 'disabled') {
    if (result.filterCatalog !== undefined) fail(`${path}.filterCatalog`);
    return { status };
  }
  const filterCatalog = object(result.filterCatalog, `${path}.filterCatalog`);
  literal(filterCatalog.version, 1, `${path}.filterCatalog.version`);
  const digest = boundedString(filterCatalog.digest, `${path}.filterCatalog.digest`, 64, 64);
  if (!/^[a-f0-9]{64}$/u.test(digest)) fail(`${path}.filterCatalog.digest`);
  literal(filterCatalog.requiresClientTimeZone, true, `${path}.filterCatalog.requiresClientTimeZone`);
  return { status, filterCatalog: { version: 1, digest, requiresClientTimeZone: true } };
}

export function decodeAgentV2ToolResultAck(value: unknown): AgentToolResultAckV2 {
  const result = object(value, '$');
  protocol(result, '$');
  const runId = uuid(result.runId, '$.runId');
  const toolCallId = uuid(result.toolCallId, '$.toolCallId');
  const clientToolResultId = uuid(result.clientToolResultId, '$.clientToolResultId');
  literal(result.accepted, true, '$.accepted');
  const duplicate = result.duplicate === undefined ? undefined : boolean(result.duplicate, '$.duplicate');
  return {
    protocolVersion: 3,
    runId,
    toolCallId,
    clientToolResultId,
    accepted: true,
    ...(duplicate !== undefined && { duplicate }),
  };
}
