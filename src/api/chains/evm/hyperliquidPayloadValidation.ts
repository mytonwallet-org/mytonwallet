import { isAddress, TypedDataEncoder } from 'ethers';

import type { ApiPerpsExchangeTypedData, ApiPerpsPermitData } from '../../types';

const HYPERLIQUID_CHAIN = 'Mainnet';
const HYPERLIQUID_SIGNATURE_CHAIN_ID = '0xa4b1';
export const HYPERLIQUID_BRIDGE_CHAIN_ID = 42161;
const HYPERLIQUID_CCTP_ARBITRUM_DOMAIN = 3;
const HYPERLIQUID_CCTP_WITHDRAW_GAS_LIMIT = 200_000;
const HYPERLIQUID_CCTP_WITHDRAW_SOURCE_DEX_PERPS = '';
const HYPERLIQUID_CCTP_WITHDRAW_SOURCE_DEX_SPOT = 'spot';

const HYPERLIQUID_BUILDER_ADDRESS = '0x09e8ed1a77387a6e4be4f0ee7ad2f6e1917a768b';
const HYPERLIQUID_BUILDER_MAX_FEE_RATE = '0.1%';
/** Fee in bps / 10, so 88 = 0.088% */
const HYPERLIQUID_BUILDER_ORDER_FEE = 88;

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const SEND_TO_EVM_PRIMARY_TYPE = 'HyperliquidTransaction:SendToEvmWithData';

const L1_AGENT_DOMAIN = {
  chainId: 1337,
  name: 'Exchange',
  verifyingContract: ZERO_ADDRESS,
  version: '1',
} as const;

const L1_AGENT_TYPES = {
  Agent: [
    { name: 'source', type: 'string' },
    { name: 'connectionId', type: 'bytes32' },
  ],
} as const;

const USER_SIGN_DOMAIN_BASE = {
  name: 'HyperliquidSignTransaction',
  version: '1',
  verifyingContract: ZERO_ADDRESS,
} as const;

const APPROVE_BUILDER_FEE_FIELDS = [
  { name: 'hyperliquidChain', type: 'string' },
  { name: 'maxFeeRate', type: 'string' },
  { name: 'builder', type: 'address' },
  { name: 'nonce', type: 'uint64' },
] as const;

const USD_CLASS_TRANSFER_FIELDS = [
  { name: 'hyperliquidChain', type: 'string' },
  { name: 'amount', type: 'string' },
  { name: 'toPerp', type: 'bool' },
  { name: 'nonce', type: 'uint64' },
] as const;

const HYPERLIQUID_SEND_TO_EVM_EIP712_FIELDS = [
  { name: 'hyperliquidChain', type: 'string' },
  { name: 'token', type: 'string' },
  { name: 'amount', type: 'string' },
  { name: 'sourceDex', type: 'string' },
  { name: 'destinationRecipient', type: 'string' },
  { name: 'addressEncoding', type: 'string' },
  { name: 'destinationChainId', type: 'uint32' },
  { name: 'gasLimit', type: 'uint64' },
  { name: 'data', type: 'bytes' },
  { name: 'nonce', type: 'uint64' },
] as const;

class HyperliquidPayloadValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'HyperliquidPayloadValidationError';
  }
}

function hyperliquidAddressMatches(actual: string, expected: string): boolean {
  return actual.toLowerCase() === expected.toLowerCase();
}

function assertRecord(value: unknown, label: string): asserts value is Record<string, unknown> {
  if (typeof value !== 'object' || !value || Array.isArray(value)) {
    throw new HyperliquidPayloadValidationError(`${label} must be an object`);
  }
}

function normalizeHyperliquidDigestHex(hashHex: string): string {
  const trimmed = hashHex.trim().toLowerCase();
  const body = trimmed.startsWith('0x') ? trimmed.slice(2) : trimmed;
  if (!/^[0-9a-f]{64}$/u.test(body)) {
    throw new HyperliquidPayloadValidationError('Hyperliquid exchange digest must be 32-byte hex');
  }
  return `0x${body}`;
}

function eip712MessageFromAction(
  action: Record<string, unknown>,
  fields: ReadonlyArray<{ name: string; type: string }>,
): Record<string, unknown> {
  const message: Record<string, unknown> = {};
  for (const { name } of fields) {
    if (!(name in action)) {
      throw new HyperliquidPayloadValidationError(`Action missing ${name}`);
    }
    message[name] = action[name];
  }
  return message;
}

function hyperliquidUserSignDomain(chainId: number) {
  return {
    ...USER_SIGN_DOMAIN_BASE,
    chainId,
  };
}

function buildUserSignedTypedData(
  primaryType: string,
  fields: ReadonlyArray<{ name: string; type: string }>,
  action: Record<string, unknown>,
  domainChainId: number,
): ApiPerpsExchangeTypedData {
  return {
    domain: hyperliquidUserSignDomain(domainChainId),
    types: { [primaryType]: [...fields] },
    primaryType,
    message: eip712MessageFromAction(action, fields),
  };
}

/** User-signed HL actions only (reconstructed locally from wire fields). */
function buildHyperliquidUserSignedTypedData(
  action: Record<string, unknown>,
  nonce: number,
): ApiPerpsExchangeTypedData {
  const actionType = action.type as string ?? '';

  if (actionType === 'approveBuilderFee') {
    const chainId = Number.parseInt(String(action.signatureChainId), 16);
    if (!Number.isFinite(chainId)) {
      throw new HyperliquidPayloadValidationError('approveBuilderFee signatureChainId is invalid');
    }
    return buildUserSignedTypedData(
      'HyperliquidTransaction:ApproveBuilderFee',
      APPROVE_BUILDER_FEE_FIELDS,
      action,
      chainId,
    );
  }

  if (actionType === 'usdClassTransfer') {
    const chainId = Number.parseInt(String(action.signatureChainId), 16);
    if (!Number.isFinite(chainId)) {
      throw new HyperliquidPayloadValidationError('spotToPerp signatureChainId is invalid');
    }
    return buildUserSignedTypedData(
      'HyperliquidTransaction:UsdClassTransfer',
      USD_CLASS_TRANSFER_FIELDS,
      action,
      chainId,
    );
  }

  if (actionType === 'sendToEvmWithData') {
    return buildUserSignedTypedData(
      SEND_TO_EVM_PRIMARY_TYPE,
      HYPERLIQUID_SEND_TO_EVM_EIP712_FIELDS,
      action,
      HYPERLIQUID_BRIDGE_CHAIN_ID,
    );
  }

  throw new HyperliquidPayloadValidationError(`Unsupported exchange action type ${actionType}`);
}

function hyperliquidExchangeSignDigest(typedData: ApiPerpsExchangeTypedData): string {
  const { EIP712Domain, ...typesForHash } = typedData.types;
  void EIP712Domain;
  return TypedDataEncoder.hash(typedData.domain, typesForHash, typedData.message);
}

function isUserSignedExchangeActionType(actionType: string): boolean {
  return actionType === 'approveBuilderFee'
    || actionType === 'usdClassTransfer'
    || actionType === 'sendToEvmWithData';
}

function assertL1AgentTypedData(typedData: ApiPerpsExchangeTypedData): void {
  if (typedData.primaryType !== 'Agent') {
    throw new HyperliquidPayloadValidationError('L1 exchange build must use Agent typedData');
  }

  const domain = typedData.domain;
  if (domain.name !== L1_AGENT_DOMAIN.name || domain.version !== L1_AGENT_DOMAIN.version) {
    throw new HyperliquidPayloadValidationError('L1 Agent domain name or version is invalid');
  }
  if (Number(domain.chainId) !== L1_AGENT_DOMAIN.chainId) {
    throw new HyperliquidPayloadValidationError('L1 Agent domain chainId must be 1337');
  }
  if (domain.verifyingContract !== ZERO_ADDRESS) {
    throw new HyperliquidPayloadValidationError('L1 Agent verifyingContract is invalid');
  }

  const agentTypes = typedData.types.Agent;
  if (!Array.isArray(agentTypes) || agentTypes.length !== L1_AGENT_TYPES.Agent.length) {
    throw new HyperliquidPayloadValidationError('L1 Agent typedData types are invalid');
  }

  if (agentTypes.some((field, index) => field.name !== L1_AGENT_TYPES.Agent[index].name
    || field.type !== L1_AGENT_TYPES.Agent[index].type)) {
    throw new HyperliquidPayloadValidationError('L1 Agent typedData fields are invalid');
  }

  if (typedData.message.source !== 'a') {
    throw new HyperliquidPayloadValidationError('L1 Agent source must be mainnet');
  }

  normalizeHyperliquidDigestHex(String(typedData.message.connectionId));
}

function assertHyperliquidServiceOrderBuilder(action: Record<string, unknown>): void {
  assertRecord(action.builder, 'action.builder');
  const builder = action.builder;
  if (typeof builder.b !== 'string' || !hyperliquidAddressMatches(builder.b, HYPERLIQUID_BUILDER_ADDRESS)) {
    throw new HyperliquidPayloadValidationError('Order must use this service Hyperliquid builder address');
  }
  if (builder.f !== HYPERLIQUID_BUILDER_ORDER_FEE) {
    throw new HyperliquidPayloadValidationError(
      `Order builder fee must be ${HYPERLIQUID_BUILDER_ORDER_FEE} (service rate)`,
    );
  }
}

function assertHyperliquidExecuteOrderAction(action: Record<string, unknown>): void {
  if (action.type !== 'order') {
    throw new HyperliquidPayloadValidationError('Position execute only accepts signed order actions from build');
  }
  if (action.grouping !== 'na') {
    throw new HyperliquidPayloadValidationError('Order action grouping must be "na"');
  }

  assertHyperliquidServiceOrderBuilder(action);

  if (!Array.isArray(action.orders) || action.orders.length !== 1) {
    throw new HyperliquidPayloadValidationError('Order action must contain exactly one wire order');
  }

  const order = action.orders[0];
  assertRecord(order, 'order');

  if (!Number.isInteger(order.a) || (order.a as number) < 0) {
    throw new HyperliquidPayloadValidationError('Wire order asset index is invalid');
  }
  if (typeof order.b !== 'boolean') {
    throw new HyperliquidPayloadValidationError('Wire order side (b) must be boolean');
  }
  if (typeof order.p !== 'string' || !/^(?:0|[1-9]\d*)(?:\.\d*[1-9])?$/u.test(order.p)) {
    throw new HyperliquidPayloadValidationError('PerpsOrderRejected: Wire order price is invalid');
  }
  if (typeof order.s !== 'string' || !/^(?:0|[1-9]\d*)(?:\.\d*[1-9])?$/u.test(order.s)) {
    throw new HyperliquidPayloadValidationError('PerpsOrderRejected: Wire order size is invalid');
  }

  assertRecord(order.t, 'order.t');
  const orderType = order.t;
  if (!('limit' in orderType) && !('trigger' in orderType)) {
    throw new HyperliquidPayloadValidationError('Wire order type (t) must be limit or trigger');
  }
}

function assertHyperliquidExecuteApproveBuilderFeeAction(action: Record<string, unknown>): void {
  if (action.type !== 'approveBuilderFee') {
    throw new HyperliquidPayloadValidationError('approveBuilderFee action type is invalid');
  }
  if (action.hyperliquidChain !== HYPERLIQUID_CHAIN) {
    throw new HyperliquidPayloadValidationError('approveBuilderFee hyperliquidChain is invalid');
  }
  if (action.signatureChainId !== HYPERLIQUID_SIGNATURE_CHAIN_ID) {
    throw new HyperliquidPayloadValidationError('approveBuilderFee signatureChainId is invalid');
  }
  if (action.maxFeeRate !== HYPERLIQUID_BUILDER_MAX_FEE_RATE) {
    throw new HyperliquidPayloadValidationError('approveBuilderFee maxFeeRate must match service approval');
  }
  if (typeof action.builder !== 'string' || !hyperliquidAddressMatches(action.builder, HYPERLIQUID_BUILDER_ADDRESS)) {
    throw new HyperliquidPayloadValidationError('approveBuilderFee builder must be this service address');
  }
}

function assertHyperliquidExecuteUpdateIsolatedMarginAction(action: Record<string, unknown>): void {
  if (action.type !== 'updateIsolatedMargin') {
    throw new HyperliquidPayloadValidationError('updateIsolatedMargin action type is invalid');
  }
  if (!Number.isInteger(action.asset) || (action.asset as number) < 0) {
    throw new HyperliquidPayloadValidationError('updateIsolatedMargin asset index is invalid');
  }
  if (action.isBuy !== true) {
    throw new HyperliquidPayloadValidationError('updateIsolatedMargin isBuy must be true');
  }
  if (!Number.isSafeInteger(action.ntli) || (action.ntli as number) <= 0) {
    throw new HyperliquidPayloadValidationError('updateIsolatedMargin ntli must be a positive integer');
  }
}

function assertHyperliquidExecuteUpdateLeverageAction(action: Record<string, unknown>): void {
  if (action.type !== 'updateLeverage') {
    throw new HyperliquidPayloadValidationError('updateLeverage action type is invalid');
  }
  if (!Number.isInteger(action.asset) || (action.asset as number) < 0) {
    throw new HyperliquidPayloadValidationError('updateLeverage asset index is invalid');
  }
  if (!Number.isInteger(action.leverage) || (action.leverage as number) < 1) {
    throw new HyperliquidPayloadValidationError('updateLeverage leverage is invalid');
  }
  if (typeof action.isCross !== 'boolean') {
    throw new HyperliquidPayloadValidationError('updateLeverage isCross must be boolean');
  }
}

function assertHyperliquidExecuteSpotToPerpAction(
  action: Record<string, unknown>,
  expectedAmountUsdc?: string,
): void {
  if (action.type !== 'usdClassTransfer') {
    throw new HyperliquidPayloadValidationError('spotToPerp must be usdClassTransfer');
  }
  if (action.hyperliquidChain !== HYPERLIQUID_CHAIN) {
    throw new HyperliquidPayloadValidationError('spotToPerp hyperliquidChain is invalid');
  }
  if (action.signatureChainId !== HYPERLIQUID_SIGNATURE_CHAIN_ID) {
    throw new HyperliquidPayloadValidationError('spotToPerp signatureChainId is invalid');
  }
  if (action.toPerp !== true) {
    throw new HyperliquidPayloadValidationError('spotToPerp must transfer USDC into perps (toPerp true)');
  }
  if (typeof action.amount !== 'string' || action.amount === '') {
    throw new HyperliquidPayloadValidationError('spotToPerp amount is invalid');
  }

  if (expectedAmountUsdc !== undefined) {
    const expected = Number.parseFloat(expectedAmountUsdc);
    const actual = Number.parseFloat(action.amount);
    if (!Number.isFinite(expected) || !Number.isFinite(actual) || expected !== actual) {
      throw new HyperliquidPayloadValidationError('spotToPerp amount must match the credited CCTP amount from build');
    }
  }
}

function assertHyperliquidExecuteSendToEvmWithdrawAction(
  action: Record<string, unknown>,
  expectedWalletRecipient: string,
): void {
  if (action.type !== 'sendToEvmWithData') {
    throw new HyperliquidPayloadValidationError('Close withdraw must be sendToEvmWithData');
  }
  if (action.hyperliquidChain !== HYPERLIQUID_CHAIN) {
    throw new HyperliquidPayloadValidationError('Withdraw hyperliquidChain is invalid');
  }
  if (action.signatureChainId !== HYPERLIQUID_SIGNATURE_CHAIN_ID) {
    throw new HyperliquidPayloadValidationError('Withdraw signatureChainId is invalid');
  }
  if (action.token !== 'USDC') {
    throw new HyperliquidPayloadValidationError('Withdraw token must be USDC');
  }
  if (action.addressEncoding !== 'hex') {
    throw new HyperliquidPayloadValidationError('Withdraw addressEncoding must be hex');
  }
  if (action.destinationChainId !== HYPERLIQUID_CCTP_ARBITRUM_DOMAIN) {
    throw new HyperliquidPayloadValidationError('Withdraw destinationChainId is invalid');
  }
  if (action.gasLimit !== HYPERLIQUID_CCTP_WITHDRAW_GAS_LIMIT) {
    throw new HyperliquidPayloadValidationError('Withdraw gasLimit is invalid');
  }
  if (action.data !== '0x') {
    throw new HyperliquidPayloadValidationError('Withdraw data must be empty (automatic CCTP forward)');
  }
  if (typeof action.amount !== 'string' || action.amount === '') {
    throw new HyperliquidPayloadValidationError('Withdraw amount is invalid');
  }
  if (typeof action.destinationRecipient !== 'string' || !isAddress(action.destinationRecipient)) {
    throw new HyperliquidPayloadValidationError('Withdraw destinationRecipient is invalid');
  }
  const sourceDex = action.sourceDex;
  if (
    sourceDex !== HYPERLIQUID_CCTP_WITHDRAW_SOURCE_DEX_PERPS
    && sourceDex !== HYPERLIQUID_CCTP_WITHDRAW_SOURCE_DEX_SPOT
  ) {
    throw new HyperliquidPayloadValidationError('Withdraw sourceDex is invalid');
  }

  if (!hyperliquidAddressMatches(action.destinationRecipient, expectedWalletRecipient)) {
    throw new HyperliquidPayloadValidationError('Withdraw destinationRecipient must match the wallet address');
  }
}

function assertHyperliquidUserSignedNonceMatches(action: Record<string, unknown>, nonce: number): void {
  const actionNonce = Number(action.nonce ?? action.time);
  if (!Number.isFinite(actionNonce) || actionNonce !== nonce) {
    throw new HyperliquidPayloadValidationError('Exchange nonce must match action.nonce');
  }
}

export type HyperliquidExchangeSignOptions = {
  expectedSpotToPerpAmountUsdc?: string;
  /** Required for sendToEvmWithData — the user's Arbitrum wallet that must receive USDC. */
  expectedWalletRecipient?: string;
};

function assertHyperliquidExchangeActionForSigning(
  action: Record<string, unknown>,
  nonce: number,
  options?: HyperliquidExchangeSignOptions,
): void {
  const actionType = action.type as string ?? '';

  if (actionType === 'order') {
    assertHyperliquidExecuteOrderAction(action);
    return;
  }

  if (actionType === 'updateLeverage') {
    assertHyperliquidExecuteUpdateLeverageAction(action);
    return;
  }

  if (actionType === 'updateIsolatedMargin') {
    assertHyperliquidExecuteUpdateIsolatedMarginAction(action);
    return;
  }

  if (actionType === 'approveBuilderFee') {
    assertHyperliquidExecuteApproveBuilderFeeAction(action);
    assertHyperliquidUserSignedNonceMatches(action, nonce);
    return;
  }

  if (actionType === 'usdClassTransfer') {
    assertHyperliquidExecuteSpotToPerpAction(action, options?.expectedSpotToPerpAmountUsdc);
    assertHyperliquidUserSignedNonceMatches(action, nonce);
    return;
  }

  if (actionType === 'sendToEvmWithData') {
    if (!options?.expectedWalletRecipient) {
      throw new HyperliquidPayloadValidationError('Withdraw signing requires the wallet recipient address');
    }
    assertHyperliquidExecuteSendToEvmWithdrawAction(action, options.expectedWalletRecipient);
    assertHyperliquidUserSignedNonceMatches(action, nonce);
    return;
  }

  throw new HyperliquidPayloadValidationError(`Unsupported signed exchange action type ${actionType}`);
}

function assertTypedDataMatchesExpected(
  expected: ApiPerpsExchangeTypedData,
  fromBuild: ApiPerpsExchangeTypedData,
): void {
  const expectedDigest = hyperliquidExchangeSignDigest(expected);
  const buildDigest = hyperliquidExchangeSignDigest(fromBuild);

  if (expectedDigest !== buildDigest) {
    throw new HyperliquidPayloadValidationError(
      'Build typedData does not match locally derived Hyperliquid signing payload',
    );
  }
}

export function assertHyperliquidExchangeBuildIntegrity(
  params: {
    action: Record<string, unknown>;
    nonce: number;
    typedData: ApiPerpsExchangeTypedData;
  },
  options?: HyperliquidExchangeSignOptions,
): ApiPerpsExchangeTypedData {
  assertHyperliquidExchangeActionForSigning(params.action, params.nonce, options);

  const actionType = params.action.type as string ?? '';

  if (actionType === 'order' || actionType === 'updateLeverage' || actionType === 'updateIsolatedMargin') {
    if (!Number.isSafeInteger(params.nonce) || params.nonce < 0) {
      throw new HyperliquidPayloadValidationError('L1 exchange nonce must be a nonnegative safe integer');
    }
    assertL1AgentTypedData(params.typedData);
    // The configured backend constructs the venue-specific action commitment.
    return params.typedData;
  }

  if (isUserSignedExchangeActionType(actionType)) {
    const typedData = buildHyperliquidUserSignedTypedData(params.action, params.nonce);
    assertTypedDataMatchesExpected(typedData, params.typedData);
    return typedData;
  }

  throw new HyperliquidPayloadValidationError(`Unsupported signed exchange action type ${actionType}`);
}

function assertSendToEvmPermitDomain(domain: Record<string, unknown>): void {
  if (domain.name !== USER_SIGN_DOMAIN_BASE.name) {
    throw new HyperliquidPayloadValidationError('Withdraw permit domain name is invalid');
  }
  if (domain.version !== USER_SIGN_DOMAIN_BASE.version) {
    throw new HyperliquidPayloadValidationError('Withdraw permit domain version is invalid');
  }
  if (domain.verifyingContract !== ZERO_ADDRESS) {
    throw new HyperliquidPayloadValidationError('Withdraw permit verifyingContract is invalid');
  }
  const chainId = Number(domain.chainId);
  if (chainId !== HYPERLIQUID_BRIDGE_CHAIN_ID) {
    throw new HyperliquidPayloadValidationError('Withdraw permit domain chainId must be Arbitrum One');
  }
}

function assertSendToEvmPermitTypes(types: Record<string, unknown>): void {
  const keys = Object.keys(types);
  if (keys.length !== 1 || keys[0] !== SEND_TO_EVM_PRIMARY_TYPE) {
    throw new HyperliquidPayloadValidationError('Withdraw permit types must only define SendToEvmWithData');
  }

  const fields = types[SEND_TO_EVM_PRIMARY_TYPE];
  if (!Array.isArray(fields)) {
    throw new HyperliquidPayloadValidationError('Withdraw permit SendToEvmWithData types are invalid');
  }

  const expected = HYPERLIQUID_SEND_TO_EVM_EIP712_FIELDS.map(({ name, type }) => ({ name, type }));
  if (fields.length !== expected.length) {
    throw new HyperliquidPayloadValidationError('Withdraw permit field list length is invalid');
  }

  for (let i = 0; i < expected.length; i += 1) {
    const actual = fields[i] as { name?: string; type?: string };
    if (actual.name !== expected[i].name || actual.type !== expected[i].type) {
      throw new HyperliquidPayloadValidationError('Withdraw permit field list does not match SendToEvmWithData schema');
    }
  }
}

function assertPermitValuesMatchAction(
  values: Record<string, unknown>,
  action: Record<string, unknown>,
  nonce: number,
): void {
  const expectedMessage = eip712MessageFromAction(action, HYPERLIQUID_SEND_TO_EVM_EIP712_FIELDS);
  if (Number(values.nonce) !== nonce) {
    throw new HyperliquidPayloadValidationError('Withdraw permit nonce must match envelope nonce');
  }

  for (const { name } of HYPERLIQUID_SEND_TO_EVM_EIP712_FIELDS) {
    if (values[name] !== expectedMessage[name]) {
      throw new HyperliquidPayloadValidationError(`Withdraw permit value ${name} does not match wire action`);
    }
  }
}

function buildHyperliquidSendToEvmPermitData(
  action: Record<string, unknown>,
  nonce: number,
): ApiPerpsPermitData {
  const typedData = buildHyperliquidUserSignedTypedData(action, nonce);
  return {
    domain: typedData.domain,
    types: typedData.types,
    values: typedData.message,
  };
}

export function assertHyperliquidWithdrawPermitIntegrity(
  withdraw: {
    action: Record<string, unknown>;
    nonce: number;
    permitData: ApiPerpsPermitData;
    destination?: string;
  },
  expectedWalletRecipient: string,
): ApiPerpsPermitData {
  if (!isAddress(expectedWalletRecipient)) {
    throw new HyperliquidPayloadValidationError('Wallet recipient address is invalid');
  }

  if (
    withdraw.destination !== undefined
    && !hyperliquidAddressMatches(withdraw.destination, expectedWalletRecipient)
  ) {
    throw new HyperliquidPayloadValidationError('Withdraw payload destination must match the wallet address');
  }

  assertHyperliquidExchangeActionForSigning(withdraw.action, withdraw.nonce, {
    expectedWalletRecipient,
  });

  assertRecord(withdraw.permitData.domain, 'permitData.domain');
  assertSendToEvmPermitDomain(withdraw.permitData.domain);
  assertRecord(withdraw.permitData.types, 'permitData.types');
  assertSendToEvmPermitTypes(withdraw.permitData.types);
  assertRecord(withdraw.permitData.values, 'permitData.values');
  assertPermitValuesMatchAction(withdraw.permitData.values, withdraw.action, withdraw.nonce);

  const permitData = buildHyperliquidSendToEvmPermitData(withdraw.action, withdraw.nonce);
  const expectedDigest = hyperliquidExchangeSignDigest({
    domain: permitData.domain,
    types: permitData.types as ApiPerpsExchangeTypedData['types'],
    primaryType: SEND_TO_EVM_PRIMARY_TYPE,
    message: permitData.values,
  });
  const buildDigest = hyperliquidExchangeSignDigest({
    domain: withdraw.permitData.domain,
    types: withdraw.permitData.types as ApiPerpsExchangeTypedData['types'],
    primaryType: SEND_TO_EVM_PRIMARY_TYPE,
    message: withdraw.permitData.values,
  });

  if (expectedDigest !== buildDigest) {
    throw new HyperliquidPayloadValidationError('Withdraw permitData does not match the wire action');
  }

  if (
    !hyperliquidAddressMatches(
      String(withdraw.permitData.values.destinationRecipient),
      expectedWalletRecipient,
    )
  ) {
    throw new HyperliquidPayloadValidationError('Withdraw permit recipient must match the wallet address');
  }

  return permitData;
}
