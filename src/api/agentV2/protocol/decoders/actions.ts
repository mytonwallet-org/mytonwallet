import type {
  AgentPersistedActionV2,
  AgentV2LiveAction,
} from '../types';
import type {
  JsonObject,
} from '../wireReader';

import {
  AgentV2CompatibilityError,
  boolean,
  boundedInteger,
  boundedString,
  extensibleKeys,
  extensibleLiteral,
  extensibleOneOf,
  extensibleVersion,
  fail,
  integer,
  literal,
  object,
  string,
} from '../wireReader';
import {
  uuid,
} from './readers';

const STAKE_AMOUNT_KINDS = new Set(['exact', 'all']);
const SWAP_AMOUNT_SIDES = new Set(['source', 'destination']);

const ACTION_KINDS = new Set(['send', 'receive', 'stake', 'swap', 'openDapp']);
const ACTION_LABEL_CODES = {
  receive: 'open_receive',
  stake: 'open_staking',
  swap: 'open_swap',
  openDapp: 'open_external_link',
} as const;
const SEND_RECIPIENT_KINDS = new Set(['address', 'domain', 'savedAddress']);

function receiveBinding(value: unknown, path: string) {
  const result = object(value, path);
  uuid(result.sessionId, `${path}.sessionId`);
  integer(result.revision, `${path}.revision`);
  string(result.activeAccountRef, `${path}.activeAccountRef`);
  string(result.activeNetwork, `${path}.activeNetwork`);
}

function stakeBinding(value: unknown, path: string) {
  const result = object(value, path);
  extensibleKeys(result, path, ['sessionId', 'revision', 'activeAccountRef']);
  uuid(result.sessionId, `${path}.sessionId`);
  boundedInteger(result.revision, `${path}.revision`, 1, Number.MAX_SAFE_INTEGER);
  boundedString(result.activeAccountRef, `${path}.activeAccountRef`, 1, 128);
}

function swapAsset(value: unknown, path: string) {
  const result = object(value, path);
  extensibleKeys(result, path, ['slug', 'chain', 'symbol', 'name', 'tokenAddress', 'decimals']);
  boundedString(result.slug, `${path}.slug`, 1, 128);
  boundedString(result.chain, `${path}.chain`, 1, 32);
  boundedString(result.symbol, `${path}.symbol`, 1, 32);
  if (result.name !== undefined) boundedString(result.name, `${path}.name`, 1, 160);
  if (result.tokenAddress !== undefined) boundedString(result.tokenAddress, `${path}.tokenAddress`, 1, 256);
  if (result.decimals !== undefined) boundedInteger(result.decimals, `${path}.decimals`, 0, 255);
}

function swapAmount(value: unknown, path: string) {
  const result = object(value, path);
  extensibleKeys(result, path, ['value', 'valueType', 'side']);
  const amount = boundedString(result.value, `${path}.value`, 1, 128);
  if (!/^[0-9]+(?:\.[0-9]+)?$/u.test(amount) || !/[1-9]/u.test(amount)) fail(`${path}.value`);
  extensibleLiteral(result.valueType, 'decimal', `${path}.valueType`);
  extensibleOneOf(result.side, SWAP_AMOUNT_SIDES, `${path}.side`);
  return result;
}

function validateSwapFormFields(result: JsonObject, path: string) {
  if (result.sourceAsset !== undefined) swapAsset(result.sourceAsset, `${path}.sourceAsset`);
  if (result.destinationAsset !== undefined) swapAsset(result.destinationAsset, `${path}.destinationAsset`);
  if (result.amount === undefined) return;
  const amount = swapAmount(result.amount, `${path}.amount`);
  const assetKey = amount.side === 'source' ? 'sourceAsset' : 'destinationAsset';
  if (result[assetKey] === undefined) fail(`${path}.${assetKey}`);
}

function stakeAmount(value: unknown, path: string) {
  const result = object(value, path);
  const kind = extensibleOneOf(result.kind, STAKE_AMOUNT_KINDS, `${path}.kind`);
  if (kind === 'all') {
    extensibleKeys(result, path, ['kind']);
    return;
  }
  extensibleKeys(result, path, ['kind', 'value']);
  const amount = boundedString(result.value, `${path}.value`, 1, 128);
  if (!/^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/u.test(amount)) fail(`${path}.value`);
}

function stakingProductId(value: unknown, path: string) {
  const productId = boundedString(value, path, 1, 128);
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]*$/u.test(productId)) fail(path);
}

function sendRecipient(value: unknown, path: string) {
  const result = object(value, path);
  const kind = extensibleOneOf(result.kind, SEND_RECIPIENT_KINDS, `${path}.kind`);
  if (kind === 'savedAddress') {
    extensibleKeys(result, path, ['kind', 'addressRef']);
    boundedString(result.addressRef, `${path}.addressRef`, 1, 128);
    return;
  }
  extensibleKeys(result, path, ['kind', 'chain', kind]);
  boundedString(result.chain, `${path}.chain`, 1, 32);
  boundedString(result[kind], `${path}.${kind}`, 1, kind === 'address' ? 256 : 253);
}

// A key, enum value or literal this client does not know marks a newer action it cannot run, so the
// action is dropped as unsupported; a missing or malformed value of a known field fails the contract
export function action(value: unknown, path: string): asserts value is AgentV2LiveAction {
  const result = object(value, path);
  const kind = extensibleOneOf(result.kind, ACTION_KINDS, `${path}.kind`);
  if (result.schemaVersion !== undefined) {
    if (kind === 'receive') extensibleVersion(result.schemaVersion, 3, `${path}.schemaVersion`);
    else if (kind === 'stake') extensibleVersion(result.schemaVersion, 2, `${path}.schemaVersion`);
    else if (kind === 'swap') extensibleVersion(result.schemaVersion, 2, `${path}.schemaVersion`);
    else if (kind === 'openDapp' || kind === 'openSettings') {
      extensibleVersion(result.schemaVersion, 1, `${path}.schemaVersion`);
    } else throw new AgentV2CompatibilityError(`${path}.schemaVersion`);
  }
  const title = boundedString(result.title, `${path}.title`, 1, 80);
  if (title !== title.trim() || /[\r\n\t]/u.test(title)) fail(`${path}.title`);
  uuid(result.id, `${path}.id`);
  if (kind !== 'send') {
    extensibleLiteral(
      result.labelCode, ACTION_LABEL_CODES[kind as keyof typeof ACTION_LABEL_CODES], `${path}.labelCode`,
    );
  }
  boolean(result.requiresConfirmation, `${path}.requiresConfirmation`);

  if (kind === 'send') {
    extensibleLiteral(result.effect, 'open_send', `${path}.effect`);
    extensibleLiteral(result.labelCode, 'open_send', `${path}.labelCode`);
    normalizeActionFields(result, [
      'id', 'kind', 'labelCode', 'title', 'effect', 'contextBinding', 'asset', 'recipient', 'amount', 'isMaxAmount',
      'comment', 'localDraftRequired', 'requiresConfirmation',
    ]);
    receiveBinding(result.contextBinding, `${path}.contextBinding`);
    if (result.asset !== undefined) {
      const asset = object(result.asset, `${path}.asset`);
      extensibleKeys(asset, `${path}.asset`, ['slug', 'chain', 'tokenAddress']);
      boundedString(asset.slug, `${path}.asset.slug`, 1, 128);
      boundedString(asset.chain, `${path}.asset.chain`, 1, 32);
      if (asset.tokenAddress !== undefined) {
        boundedString(asset.tokenAddress, `${path}.asset.tokenAddress`, 1, 256);
      }
    } else if (result.amount !== undefined || result.isMaxAmount !== undefined) {
      fail(path);
    }
    if (result.recipient !== undefined) sendRecipient(result.recipient, `${path}.recipient`);
    if (result.amount !== undefined) {
      const amount = boundedString(result.amount, `${path}.amount`, 1, 128);
      if (!/^(?:0|[1-9]\d*)(?:\.\d+)?$/u.test(amount)) fail(`${path}.amount`);
    }
    if (result.isMaxAmount !== undefined) {
      literal(result.isMaxAmount, true, `${path}.isMaxAmount`);
      // The maximum is an amount of its own, so the two never come together
      if (result.amount !== undefined) fail(path);
    }
    if (result.comment !== undefined) boundedString(result.comment, `${path}.comment`, 1, 512);
    extensibleLiteral(result.localDraftRequired, false, `${path}.localDraftRequired`);
    extensibleLiteral(result.requiresConfirmation, false, `${path}.requiresConfirmation`);
  } else if (kind === 'receive') {
    if (result.schemaVersion === undefined) {
      normalizeActionFields(result, [
        'id', 'kind', 'labelCode', 'title', 'effect', 'contextBinding', 'localDraftRequired',
        'requiresConfirmation',
      ]);
    } else {
      normalizeActionFields(result, [
        'id', 'schemaVersion', 'kind', 'labelCode', 'title', 'effect', 'contextBinding',
        'targetNetwork', 'localDraftRequired', 'requiresConfirmation',
      ]);
      extensibleVersion(result.schemaVersion, 3, `${path}.schemaVersion`);
      boundedString(result.targetNetwork, `${path}.targetNetwork`, 1, 32);
    }
    extensibleLiteral(result.effect, 'open_receive', `${path}.effect`);
    extensibleLiteral(result.localDraftRequired, false, `${path}.localDraftRequired`);
    receiveBinding(result.contextBinding, `${path}.contextBinding`);
  } else if (kind === 'stake') {
    normalizeActionFields(result, [
      'id', 'schemaVersion', 'kind', 'labelCode', 'title', 'effect', 'contextBinding',
      'productId', 'asset', 'amount', 'localDraftRequired', 'requiresConfirmation',
    ]);
    literal(result.schemaVersion, 2, `${path}.schemaVersion`);
    stakingProductId(result.productId, `${path}.productId`);
    swapAsset(result.asset, `${path}.asset`);
    if (result.amount !== undefined) stakeAmount(result.amount, `${path}.amount`);
    extensibleLiteral(result.effect, 'open_staking', `${path}.effect`);
    extensibleLiteral(result.localDraftRequired, false, `${path}.localDraftRequired`);
    extensibleLiteral(result.requiresConfirmation, false, `${path}.requiresConfirmation`);
    stakeBinding(result.contextBinding, `${path}.contextBinding`);
  } else if (kind === 'swap') {
    normalizeActionFields(result, [
      'id', 'schemaVersion', 'kind', 'labelCode', 'title', 'effect', 'url',
      'contextBinding', 'sourceAsset', 'destinationAsset', 'amount',
      'localDraftRequired', 'requiresConfirmation',
    ]);
    literal(result.schemaVersion, 2, `${path}.schemaVersion`);
    extensibleLiteral(result.effect, 'open_swap', `${path}.effect`);
    const url = boundedString(result.url, `${path}.url`, 1, 2048);
    if (!url.startsWith('https://')) fail(`${path}.url`);
    stakeBinding(result.contextBinding, `${path}.contextBinding`);
    validateSwapFormFields(result, path);
    extensibleLiteral(result.localDraftRequired, false, `${path}.localDraftRequired`);
    extensibleLiteral(result.requiresConfirmation, false, `${path}.requiresConfirmation`);
  } else {
    navigationAction(result, kind as NavigationActionKind, path, false);
  }
}

function navigationAction(
  result: JsonObject,
  kind: NavigationActionKind,
  path: string,
  isPersisted: boolean,
) {
  const commonKeys = ['id', 'schemaVersion', 'kind', 'labelCode', 'title'];
  extensibleLiteral(result.requiresConfirmation, true, `${path}.requiresConfirmation`);
  literal(result.schemaVersion, isPersisted ? 3 : 1, `${path}.schemaVersion`);
  switch (kind) {
    case 'openDapp': {
      normalizeActionFields(result, [...commonKeys, 'url', 'requiresConfirmation']);
      boundedString(result.url, `${path}.url`, 1, 2048);
      return;
    }
    default:
      return assertUnreachableContract(kind, `${path}.kind`);
  }
}

type NavigationActionKind = 'openDapp';

function assertUnreachableContract(_value: never, path: string): never {
  fail(path);
}

export function persistedAction(value: unknown, path: string): asserts value is AgentPersistedActionV2 {
  const result = object(value, path);
  if (result.contextBinding !== undefined || result.sourceToolCallId !== undefined) fail(path);
  const kind = extensibleOneOf(result.kind, ACTION_KINDS, `${path}.kind`);
  if (result.schemaVersion !== undefined) {
    if (kind === 'stake') extensibleVersion(result.schemaVersion, 2, `${path}.schemaVersion`);
    else if (kind === 'swap') extensibleVersion(result.schemaVersion, 2, `${path}.schemaVersion`);
    else extensibleVersion(result.schemaVersion, 3, `${path}.schemaVersion`);
    if (kind === 'send') throw new AgentV2CompatibilityError(`${path}.schemaVersion`);
  }
  const title = boundedString(result.title, `${path}.title`, 1, 80);
  if (title !== title.trim() || /[\r\n\t]/u.test(title)) fail(`${path}.title`);
  uuid(result.id, `${path}.id`);
  if (kind !== 'send') {
    extensibleLiteral(
      result.labelCode, ACTION_LABEL_CODES[kind as keyof typeof ACTION_LABEL_CODES], `${path}.labelCode`,
    );
  }
  if (kind === 'send') {
    extensibleLiteral(result.effect, 'live_only', `${path}.effect`);
    extensibleLiteral(result.labelCode, 'open_send', `${path}.labelCode`);
    normalizeActionFields(result, [
      'id', 'kind', 'labelCode', 'title', 'effect', 'localDraftRequired', 'requiresConfirmation',
    ]);
    extensibleLiteral(result.localDraftRequired, false, `${path}.localDraftRequired`);
    extensibleLiteral(result.requiresConfirmation, false, `${path}.requiresConfirmation`);
  } else if (kind === 'receive') {
    if (result.schemaVersion === undefined) {
      normalizeActionFields(result, [
        'id', 'kind', 'labelCode', 'title', 'effect', 'localDraftRequired', 'requiresConfirmation',
      ]);
    } else {
      normalizeActionFields(result, [
        'id', 'schemaVersion', 'kind', 'labelCode', 'title', 'effect', 'targetNetwork',
        'localDraftRequired', 'requiresConfirmation',
      ]);
      extensibleVersion(result.schemaVersion, 3, `${path}.schemaVersion`);
      boundedString(result.targetNetwork, `${path}.targetNetwork`, 1, 32);
    }
    extensibleLiteral(result.effect, 'open_receive', `${path}.effect`);
    extensibleLiteral(result.localDraftRequired, false, `${path}.localDraftRequired`);
    extensibleLiteral(result.requiresConfirmation, false, `${path}.requiresConfirmation`);
  } else if (kind === 'stake') {
    normalizeActionFields(result, [
      'id', 'schemaVersion', 'kind', 'labelCode', 'title', 'effect', 'productId', 'asset',
      'amount', 'localDraftRequired', 'requiresConfirmation',
    ]);
    literal(result.schemaVersion, 2, `${path}.schemaVersion`);
    stakingProductId(result.productId, `${path}.productId`);
    swapAsset(result.asset, `${path}.asset`);
    if (result.amount !== undefined) stakeAmount(result.amount, `${path}.amount`);
    extensibleLiteral(result.effect, 'open_staking', `${path}.effect`);
    extensibleLiteral(result.localDraftRequired, false, `${path}.localDraftRequired`);
    extensibleLiteral(result.requiresConfirmation, false, `${path}.requiresConfirmation`);
  } else if (kind === 'swap') {
    normalizeActionFields(result, [
      'id', 'schemaVersion', 'kind', 'labelCode', 'title', 'effect', 'url', 'sourceAsset',
      'destinationAsset', 'amount', 'localDraftRequired', 'requiresConfirmation',
    ]);
    literal(result.schemaVersion, 2, `${path}.schemaVersion`);
    extensibleLiteral(result.effect, 'open_swap', `${path}.effect`);
    const url = boundedString(result.url, `${path}.url`, 1, 2048);
    if (!url.startsWith('https://')) fail(`${path}.url`);
    validateSwapFormFields(result, path);
    extensibleLiteral(result.localDraftRequired, false, `${path}.localDraftRequired`);
    extensibleLiteral(result.requiresConfirmation, false, `${path}.requiresConfirmation`);
  } else {
    navigationAction(result, kind as NavigationActionKind, path, true);
  }
}

export function decodeAgentV2Action(value: unknown): AgentV2LiveAction {
  const result = object(value, '$');
  action(result, '$');
  return result;
}

export function decodeAgentV2PersistedAction(value: unknown): AgentPersistedActionV2 {
  const result = object(value, '$');
  persistedAction(result, '$');
  return result;
}

function normalizeActionFields(value: JsonObject, keys: readonly string[]) {
  for (const key of Object.keys(value)) {
    if (!keys.includes(key)) delete value[key];
  }
}
