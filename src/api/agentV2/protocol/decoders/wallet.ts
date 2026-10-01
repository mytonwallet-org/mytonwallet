import type {
  AgentToolCall,
  AgentToolResultAckV2,
  AgentWalletConversationContextV5,
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

const SAFE_STAKING_PRODUCT_ID_PATTERN = /^[A-Za-z0-9._:-]{1,64}$/u;

const MIN_TOOL_TIMEOUT_MS = 100;

const MAX_TOOL_TIMEOUT_MS = 30_000;

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
    case 'action.send.prepare':
      object(args.asset, `${path}.arguments.asset`);
      object(args.amount, `${path}.arguments.amount`);
      object(args.recipient, `${path}.arguments.recipient`);
      break;
    case 'action.swap.prepare': {
      strictKeys(args, `${path}.arguments`, [
        'schemaVersion', 'sourceSelector', 'destinationSelector', 'amount',
      ]);
      literal(args.schemaVersion, 1, `${path}.arguments.schemaVersion`);
      validateSwapSelector(args.sourceSelector, `${path}.arguments.sourceSelector`);
      validateSwapSelector(args.destinationSelector, `${path}.arguments.destinationSelector`);
      const amount = object(args.amount, `${path}.arguments.amount`);
      strictKeys(amount, `${path}.arguments.amount`, ['value', 'valueType', 'side']);
      const value = boundedString(amount.value, `${path}.arguments.amount.value`, 1, 128);
      if (!/^[0-9]+(?:\.[0-9]+)?$/u.test(value) || !/[1-9]/u.test(value)) {
        fail(`${path}.arguments.amount.value`);
      }
      literal(amount.valueType, 'decimal', `${path}.arguments.amount.valueType`);
      oneOf(amount.side, new Set(['source', 'destination']), `${path}.arguments.amount.side`);
      break;
    }
    case 'wallet.data.query': {
      validateWalletDataQueryV5(args, `${path}.arguments`);
      break;
    }
    case 'wallet.directory.query': {
      strictKeys(args, `${path}.arguments`, ['schemaVersion', 'purpose']);
      literal(args.schemaVersion, 1, `${path}.arguments.schemaVersion`);
      literal(args.purpose, 'send_wallet_resolution', `${path}.arguments.purpose`);
      break;
    }
    case 'market.asset.quote': {
      const isAssetQuote = 'quoteAsset' in args;
      strictKeys(args, `${path}.arguments`, [
        'schemaVersion', isAssetQuote ? 'quoteAsset' : 'quoteCurrency', 'selector',
      ]);
      literal(args.schemaVersion, 1, `${path}.arguments.schemaVersion`);
      if (isAssetQuote) {
        validateMarketAssetIdentity(args.quoteAsset, `${path}.arguments.quoteAsset`);
      } else {
        const quoteCurrency = boundedString(args.quoteCurrency, `${path}.arguments.quoteCurrency`, 3, 8);
        if (!/^[A-Z]{3,8}$/u.test(quoteCurrency)) fail(`${path}.arguments.quoteCurrency`);
      }
      const selector = object(args.selector, `${path}.arguments.selector`);
      const kind = oneOf(selector.kind, new Set(['query', 'asset']), `${path}.arguments.selector.kind`);
      if (kind === 'query') {
        strictKeys(selector, `${path}.arguments.selector`, ['kind', 'query', 'chain']);
        boundedString(selector.query, `${path}.arguments.selector.query`, 1, 160);
        if (selector.chain !== undefined) {
          oneOf(selector.chain, new Set(['ton', 'tron', 'solana', 'ethereum']), `${path}.arguments.selector.chain`);
        }
      } else {
        strictKeys(selector, `${path}.arguments.selector`, ['kind', 'asset']);
        validateMarketAssetIdentity(selector.asset, `${path}.arguments.selector.asset`);
      }
      break;
    }
    case 'staking.offer.read': {
      strictKeys(args, `${path}.arguments`, ['schemaVersion', 'productId', 'asset']);
      literal(args.schemaVersion, 1, `${path}.arguments.schemaVersion`);
      const productId = boundedString(args.productId, `${path}.arguments.productId`, 1, 64);
      if (!SAFE_STAKING_PRODUCT_ID_PATTERN.test(productId)) fail(`${path}.arguments.productId`);
      validateAssetIdentity(args.asset, `${path}.arguments.asset`);
      break;
    }
    case 'staking.offers.list': {
      strictKeys(args, `${path}.arguments`, ['schemaVersion']);
      literal(args.schemaVersion, 1, `${path}.arguments.schemaVersion`);
      break;
    }
  }
}

function validateSwapSelector(value: unknown, path: string) {
  const selector = object(value, path);
  strictKeys(selector, path, ['kind', 'query', 'chain']);
  literal(selector.kind, 'query', `${path}.kind`);
  boundedString(selector.query, `${path}.query`, 1, 160);
  if (selector.chain !== undefined) {
    oneOf(selector.chain, new Set(['ton', 'tron', 'solana', 'ethereum']), `${path}.chain`);
  }
}

function validateAssetIdentity(value: unknown, path: string) {
  const result = object(value, path);
  strictKeys(result, path, ['slug', 'chain', 'symbol', 'name', 'tokenAddress', 'decimals']);
  boundedString(result.slug, `${path}.slug`, 1, 128);
  boundedString(result.chain, `${path}.chain`, 1, 32);
  boundedString(result.symbol, `${path}.symbol`, 1, 32);
  if (result.name !== undefined) boundedString(result.name, `${path}.name`, 1, 160);
  if (result.tokenAddress !== undefined) boundedString(result.tokenAddress, `${path}.tokenAddress`, 1, 256);
  if (result.decimals !== undefined) boundedInteger(result.decimals, `${path}.decimals`, 0, 255);
}

function validateMarketAssetIdentity(value: unknown, path: string) {
  validateAssetIdentity(value, path);
  const result = object(value, path);
  oneOf(result.chain, new Set(['ton', 'tron', 'solana', 'ethereum']), `${path}.chain`);
}

export function toolCall(value: unknown, path: string) {
  const result = object(value, path);
  uuid(result.id, `${path}.id`);
  const name = oneOf<AgentToolCall['name']>(result.name, TOOL_NAMES, `${path}.name`);
  boundedInteger(result.version, `${path}.version`, 1, 100);
  if (result.maxResultBytes !== undefined) {
    boundedInteger(result.maxResultBytes, `${path}.maxResultBytes`, 1, 98_304);
  }
  const scopes = array(result.scopes, `${path}.scopes`);
  if (scopes.length !== 1 || scopes[0] !== TOOL_SCOPES[name]) fail(`${path}.scopes`);
  boundedInteger(result.timeoutMs, `${path}.timeoutMs`, MIN_TOOL_TIMEOUT_MS, MAX_TOOL_TIMEOUT_MS);
  if (name === 'staking.offer.read' || name === 'staking.offers.list') {
    literal(result.version, 1, `${path}.version`);
    literal(result.maxResultBytes, 16_384, `${path}.maxResultBytes`);
    literal(result.timeoutMs, 15_000, `${path}.timeoutMs`);
  }
  validateIntentSource(result, path);
  validateScopeIntent(result, path);
  if (name === 'wallet.directory.query') {
    literal(result.version, 1, `${path}.version`);
    boundedInteger(result.maxResultBytes, `${path}.maxResultBytes`, 1, 32_768);
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

function validateWalletDataQueryV5(args: JsonObject, path: string) {
  literal(args.schemaVersion, 5, `${path}.schemaVersion`);
  const operation = oneOf(args.operation, new Set([
    'account.inventory', 'assets.search', 'positions.list', 'portfolio.aggregate',
    'transactions.list', 'transactions.detail', 'contacts.list', 'value.series',
  ]), `${path}.operation`);
  if (operation === 'assets.search') {
    strictKeys(args, path, ['schemaVersion', 'operation', 'query', 'chains', 'pageSize']);
    boundedString(args.query, `${path}.query`, 1, 160);
    validateUniqueStringArray(args.chains, `${path}.chains`, 16);
    boundedInteger(args.pageSize, `${path}.pageSize`, 1, 10);
    return;
  }

  validateWalletAccountSelector(args.accountSelector, `${path}.accountSelector`, true);
  if (operation === 'account.inventory') {
    strictKeys(args, path, [
      'schemaVersion', 'operation', 'accountSelector', 'chains', 'includePublicAddressReason',
      'includePortfolioTotals',
    ]);
    validateUniqueStringArray(args.chains, `${path}.chains`, 16);
    if (args.includePublicAddressReason !== undefined) {
      oneOf(args.includePublicAddressReason, new Set([
        'receive', 'wallet_location', 'prepare_validation',
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
      'schemaVersion', 'operation', 'accountSelector', 'chains', 'assetSelectors',
      'positionKinds', 'riskMode', 'visibilityMode', 'includeZero', 'sort', 'pageSize',
    ]);
    validateUniqueStringArray(args.chains, `${path}.chains`, 16);
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
      'schemaVersion', 'operation', 'accountSelector', 'accountFilter', 'chains', 'range', 'groupBy',
      'riskMode', 'visibilityMode',
    ]);
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
    validateUniqueStringArray(args.chains, `${path}.chains`, 16);
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
      'schemaVersion', 'operation', 'accountSelector', 'chains', 'filters', 'riskMode', 'pageSize',
    ]);
    validateUniqueStringArray(args.chains, `${path}.chains`, 16);
    validateWalletFilterSet(args.filters, `${path}.filters`);
    oneOf(args.riskMode, new Set(['exclude', 'only', 'all']), `${path}.riskMode`);
    boundedInteger(args.pageSize, `${path}.pageSize`, 1, 50);
    return;
  }
  if (operation === 'transactions.detail') {
    strictKeys(args, path, ['schemaVersion', 'operation', 'accountSelector', 'hash']);
    const hash = boundedString(args.hash, `${path}.hash`, 43, 128);
    if (!FULL_TRANSACTION_HASH_PATTERN.test(hash)) fail(`${path}.hash`);
    return;
  }
  if (operation === 'contacts.list') {
    strictKeys(args, path, [
      'schemaVersion', 'operation', 'accountSelector', 'query', 'chains', 'pageSize',
    ]);
    if (!isWireNull(args.query)) boundedString(args.query, `${path}.query`, 1, 120);
    validateUniqueStringArray(args.chains, `${path}.chains`, 16);
    boundedInteger(args.pageSize, `${path}.pageSize`, 1, 100);
    return;
  }
  strictKeys(args, path, [
    'schemaVersion', 'operation', 'accountSelector', 'chains', 'metric', 'assetSelectors',
    'range', 'maxPoints',
  ]);
  validateUniqueStringArray(args.chains, `${path}.chains`, 16);
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
        else validateUniqueStringArray(clause.values, `${clausePath}.values`, 16);
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
      ? ['current', 'named', 'ordinal', 'anchored', 'explicitAll']
      : ['current', 'named', 'explicitAll']),
    `${path}.kind`,
  );
  strictKeys(selector, path, selectorKind === 'named' ? ['kind', 'label']
    : selectorKind === 'ordinal' ? ['kind', 'index']
      : selectorKind === 'anchored' ? ['kind', 'scopeAnchor', 'label'] : ['kind']);
  if (selectorKind === 'named' || selectorKind === 'anchored') {
    boundedString(selector.label, `${path}.label`, 1, 80);
  }
  if (selectorKind === 'ordinal') boundedInteger(selector.index, `${path}.index`, 1, 100);
  if (selectorKind === 'anchored') {
    const anchor = boundedString(selector.scopeAnchor, `${path}.scopeAnchor`, 28, 134);
    if (!/^scope_[A-Za-z0-9_-]{22,128}$/u.test(anchor)) fail(`${path}.scopeAnchor`);
  }
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

function validateUniqueStringArray(value: unknown, path: string, maxLength: number) {
  const items = array(value, path, maxLength)
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
      : ['named', 'ordinal', 'anchored'].includes(String(selector.kind)) ? 'selected' : 'current';
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
  if (sessionScope !== 'current' || tool.scopeIntent !== undefined) fail(`${path}.walletContextSession.accountScope`);
}

export function walletConversationContextV5(
  value: unknown,
  path: string,
): asserts value is AgentWalletConversationContextV5 {
  const result = object(value, path);
  strictKeys(result, path, [
    'schemaVersion', 'sourceAssistantMessageId', 'sessionId', 'revision', 'operation',
    'query', 'scopeChoices', 'expiresAt',
  ]);
  literal(result.schemaVersion, 5, `${path}.schemaVersion`);
  uuid(result.sourceAssistantMessageId, `${path}.sourceAssistantMessageId`);
  uuid(result.sessionId, `${path}.sessionId`);
  boundedInteger(result.revision, `${path}.revision`, 1, Number.MAX_SAFE_INTEGER);
  const operation = oneOf(result.operation, new Set([
    'account.inventory', 'positions.list', 'portfolio.aggregate', 'transactions.list',
    'transactions.detail', 'contacts.list', 'value.series',
  ]), `${path}.operation`);
  const query = object(result.query, `${path}.query`);
  validateWalletDataQueryV5(query, `${path}.query`);
  if (query.operation !== operation) fail(`${path}.query.operation`);
  timestamp(result.expiresAt, `${path}.expiresAt`);
  const choices = array(result.scopeChoices, `${path}.scopeChoices`, 5);
  if (!choices.length) fail(`${path}.scopeChoices`);
  choices.forEach((item, index) => {
    const choicePath = `${path}.scopeChoices[${index}]`;
    const choice = object(item, choicePath);
    strictKeys(choice, choicePath, ['choiceId', 'scopeAnchor', 'label', 'ordinal', 'chains']);
    const choiceId = boundedString(choice.choiceId, `${choicePath}.choiceId`, 29, 135);
    if (!/^choice_[A-Za-z0-9_-]{22,128}$/u.test(choiceId)) fail(`${choicePath}.choiceId`);
    const anchor = boundedString(choice.scopeAnchor, `${choicePath}.scopeAnchor`, 28, 134);
    if (!/^scope_[A-Za-z0-9_-]{22,128}$/u.test(anchor)) fail(`${choicePath}.scopeAnchor`);
    boundedString(choice.label, `${choicePath}.label`, 1, 80);
    boundedInteger(choice.ordinal, `${choicePath}.ordinal`, 1, 100);
    if (choice.chains !== undefined) validateUniqueStringArray(choice.chains, `${choicePath}.chains`, 16);
  });
}

export function decodeAgentV2WalletConversationContextV5(
  value: unknown,
): AgentWalletConversationContextV5 {
  walletConversationContextV5(value, '$');
  return value;
}

export function decodeAgentV2WalletQueryCapabilitiesV2(
  value: unknown,
): {
    protocolVersion: 2;
    status: 'available' | 'disabled';
    supportedToolVersions: 5[];
    filterCatalog?: {
      version: 1;
      digest: string;
      requiresClientTimeZone: true;
    };
  } {
  const result = object(value, '$');
  protocol(result, '$');
  const status = oneOf<'available' | 'disabled'>(
    result.status,
    new Set(['available', 'disabled']),
    '$.status',
  );
  const versions = array(result.supportedToolVersions, '$.supportedToolVersions', 1);
  versions.forEach((version, index) => {
    literal(version, 5, `$.supportedToolVersions[${index}]`);
  });
  if (new Set(versions).size !== versions.length) fail('$.supportedToolVersions');
  if (status === 'available') {
    if (JSON.stringify(versions) !== '[5]') fail('$.supportedToolVersions');
    const filterCatalog = object(result.filterCatalog, '$.filterCatalog');
    literal(filterCatalog.version, 1, '$.filterCatalog.version');
    const digest = boundedString(filterCatalog.digest, '$.filterCatalog.digest', 64, 64);
    if (!/^[a-f0-9]{64}$/u.test(digest)) fail('$.filterCatalog.digest');
    literal(filterCatalog.requiresClientTimeZone, true, '$.filterCatalog.requiresClientTimeZone');
    return {
      protocolVersion: 2,
      status,
      supportedToolVersions: [5],
      filterCatalog: {
        version: 1,
        digest,
        requiresClientTimeZone: true,
      },
    };
  } else if (
    versions.length
    || result.filterCatalog !== undefined
  ) {
    fail('$.supportedToolVersions');
  }
  return { protocolVersion: 2, status, supportedToolVersions: [] };
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
    protocolVersion: 2,
    runId,
    toolCallId,
    clientToolResultId,
    accepted: true,
    ...(duplicate !== undefined && { duplicate }),
  };
}
