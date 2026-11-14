import { Interface, ZeroHash, zeroPadValue } from 'ethers';

import type { VtIntent, VtPlan, VtTransaction } from './types';

import deployments from './deployments.json';

export const VT_NATIVE_TOKEN = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
export const VT_FEE_RECIPIENT = '0xB324De4ADd083B74856082Ed2EA0B8b6F3864827';
const WRAPPER = new Interface([
  'function execute((address target,uint256 value,bytes data)[] calls, bytes32 quoteId) payable',
  'function sweep(address[] tokens, address recipient)',
]);
const DELEGATE = new Interface([
  'function delegateTransferFrom(address token,address from,address to,uint256 amount)',
]);
const TOKEN = new Interface([
  'function approve(address spender,uint256 amount)',
  'function transfer(address to,uint256 amount)',
]);
const STARGATE = new Interface([
  // eslint-disable-next-line @stylistic/max-len
  'function sendToken((uint32 dstEid,bytes32 to,uint256 amountLD,uint256 minAmountLD,bytes extraOptions,bytes composeMsg,bytes oftCmd) param,(uint256 nativeFee,uint256 lzTokenFee) fee,address refundAddress) payable',
  // eslint-disable-next-line @stylistic/max-len
  'function send((uint32 dstEid,bytes32 to,uint256 amountLD,uint256 minAmountLD,bytes extraOptions,bytes composeMsg,bytes oftCmd) param,(uint256 nativeFee,uint256 lzTokenFee) fee,address refundAddress) payable',
]);
const OFT = new Interface([
  // eslint-disable-next-line @stylistic/max-len
  'function send((uint32 dstEid,bytes32 to,uint256 amountLD,uint256 minAmountLD,bytes extraOptions,bytes composeMsg,bytes oftCmd) param,(uint256 nativeFee,uint256 lzTokenFee) fee,address refundAddress) payable',
]);
const CCTP = new Interface([
  // eslint-disable-next-line @stylistic/max-len
  'function depositForBurn(uint256 amount,uint32 destinationDomain,bytes32 mintRecipient,address burnToken,bytes32 destinationCaller,uint256 maxFee,uint32 minFinalityThreshold)',
]);
type ChainConfig = {
  key: string;
  chainId: number;
  eid: number;
  wrapper: string;
  delegate: string;
  wrapperCodeHash: string;
  delegateCodeHash: string;
  nativeGasToken?: string;
  nativeGasTokenDecimals?: number;
  cctp?: { domain: number; token: string; messenger: string };
};
export const VT_CHAINS: Record<string, ChainConfig> = deployments.chains;
type Call = { target: string; value: bigint; data: string };

/** A source deployment can belong to several groups; the route uses the group that reaches the destination */
export function findOftRoute(intent: VtIntent, target: string) {
  const sources = deployments.assets.filter(
    (entry) =>
      entry.chain === intent.sourceChain
      && isSameAddress(entry.address, target)
      && isSameAddress(entry.token, intent.sourceToken),
  );
  const outputOf = (group: string) => deployments.assets.find(
    (entry) =>
      entry.chain === intent.destinationChain
      && entry.group === group
      && isSameAddress(entry.token, intent.destinationToken),
  );
  const asset = sources.find((entry) => outputOf(entry.group)) ?? sources[0];
  return { asset, output: asset && outputOf(asset.group) };
}

/** Decodes every call against release-pinned deployments and the wallet's independently held intent */
export function validateVtPlan(plan: VtPlan, intent: VtIntent, now = Date.now()): VtTransaction {
  const source = VT_CHAINS[intent.sourceChain];
  const destination = VT_CHAINS[intent.destinationChain];
  assert(source && destination && source !== destination, 'Unsupported VT chain pair');
  assert(plan.provider === 'layerzero', 'Unsupported VT plan');
  assert(plan.expiresAt > now && plan.expiresAt <= now + 120000, 'Expired VT quote');
  const { quote } = plan;
  assert(/^0x[0-9a-fA-F]{64}$/.test(quote.id), 'Invalid VT quote ID');
  const amount = BigInt(intent.amount);
  const feeAmount = BigInt(intent.feeAmount);
  assert(amount > 0n && feeAmount >= 0n && feeAmount * 10n <= amount, 'Invalid VT fee');
  const bridgeAmount = amount - feeAmount;
  assert(BigInt(quote.srcAmount) === amount, 'VT source amount changed');
  assert(BigInt(quote.dstAmountMin) >= BigInt(intent.minimum), 'VT minimum output changed');
  assert(quote.routeSteps.length === 1, 'Unsupported VT multihop');
  const route = quote.routeSteps[0];
  assert(route.srcChainKey === source.key, 'VT route source mismatch');
  assert(['STARGATE_V2_TAXI', 'OFT_V2', 'CCTP_V2'].includes(route.type), 'Unsupported VT protocol');
  let bridge: VtTransaction | undefined;
  for (const step of quote.userSteps) {
    assert(
      step.type === 'TRANSACTION' && step.chainType === 'EVM' && step.chainKey === source.key,
      'Unsupported VT operation',
    );
    assert(isSameAddress(step.signerAddress, intent.owner), 'VT signer mismatch');
    const transaction = step.transaction?.encoded;
    assert(
      transaction && transaction.chainId === source.chainId && isSameAddress(transaction.from, intent.owner),
      'VT transaction chain or owner mismatch',
    );
    if (isSameAddress(transaction.to, intent.sourceToken) && transaction.data.startsWith('0x095ea7b3')) {
      const approval = TOKEN.decodeFunctionData('approve', transaction.data);
      assert(
        !isSameAddress(intent.sourceToken, VT_NATIVE_TOKEN)
        && isSameAddress(approval[0], source.delegate)
        && BigInt(approval[1].toString()) === amount
        && BigInt(transaction.value ?? '0') === 0n,
        'Untrusted VT approval',
      );
    } else {
      assert(!bridge && isSameAddress(transaction.to, source.wrapper), 'Untrusted VT execution target');
      bridge = transaction;
    }
  }
  assert(bridge, 'Missing VT bridge transaction');
  const decoded = WRAPPER.decodeFunctionData('execute', bridge.data);
  assert(isSameAddress(decoded[1], quote.id), 'VT quote ID mismatch');
  const calls: Call[] = decoded[0].map(
    (call: { target: string; value: { toString(): string }; data: string }) => ({
      target: call.target,
      value: BigInt(call.value.toString()),
      data: call.data,
    }),
  );
  const isNative = isSameAddress(intent.sourceToken, VT_NATIVE_TOKEN);
  let index = 0;
  if (!isNative) {
    const pull = calls[index++];
    assert(pull && isSameAddress(pull.target, source.delegate) && pull.value === 0n, 'Missing VT token pull');
    const transfer = DELEGATE.decodeFunctionData('delegateTransferFrom', pull.data);
    assert(
      isSameAddress(transfer[0], intent.sourceToken)
      && isSameAddress(transfer[1], intent.owner)
      && isSameAddress(transfer[2], source.wrapper)
      && BigInt(transfer[3].toString()) === amount,
      'Invalid VT token pull',
    );
  }
  const partnerFees = quote.fees.filter((fee) => fee.type === 'GENERAL');
  const collectedFee = partnerFees.reduce((sum, fee) => sum + BigInt(fee.amount), 0n);
  // On OFT_V2 VT adds its own 2 bps fee to our partner fee in one transfer; a higher one fails closed
  let protocolFee = route.type === 'OFT_V2' ? collectedFee - feeAmount : 0n;
  assert(partnerFees.every((fee) => fee.chainKey === source.key && isSameAddress(fee.address, intent.sourceToken))
    && protocolFee >= 0n && protocolFee <= amount / 5000n && collectedFee === feeAmount + protocolFee,
  'VT partner fee mismatch');
  if (collectedFee > 0n) {
    const call = calls[index++];
    assert(call, 'Missing VT partner fee');
    if (isNative) {
      assert(isSameAddress(call.target, VT_FEE_RECIPIENT) && call.value === collectedFee && call.data === '0x',
        'Invalid VT partner fee');
    } else {
      assert(isSameAddress(call.target, intent.sourceToken) && call.value === 0n, 'Invalid VT partner fee token');
      const transfer = TOKEN.decodeFunctionData('transfer', call.data);
      assert(isSameAddress(transfer[0], VT_FEE_RECIPIENT) && BigInt(transfer[1].toString()) === collectedFee,
        'Invalid VT partner fee');
    }
  }
  if (route.type === 'CCTP_V2' && calls[index]?.data.startsWith('0xa9059cbb')) {
    const call = calls[index++];
    assert(isSameAddress(call.target, intent.sourceToken) && call.value === 0n, 'Invalid CCTP receive fee');
    const transfer = TOKEN.decodeFunctionData('transfer', call.data);
    protocolFee = BigInt(transfer[1].toString());
    assert(
      isSameAddress(transfer[0], VT_FEE_RECIPIENT) && protocolFee <= bridgeAmount / 100n,
      'CCTP receive fee exceeds policy',
    );
  }
  const approval = !isNative && calls[index]?.data.startsWith('0x095ea7b3') ? calls[index++] : undefined;
  const send = calls[index++];
  assert(send, 'Missing VT protocol call');
  if (approval) {
    assert(
      isSameAddress(approval.target, intent.sourceToken) && approval.value === 0n,
      'Invalid VT router approval',
    );
    const approve = TOKEN.decodeFunctionData('approve', approval.data);
    assert(
      isSameAddress(approve[0], send.target) && BigInt(approve[1].toString()) === bridgeAmount - protocolFee,
      'Invalid VT router allowance',
    );
  }
  if (route.type === 'CCTP_V2') {
    assert(
      source.cctp
      && destination.cctp
      && isSameAddress(send.target, source.cctp.messenger)
      && isSameAddress(intent.sourceToken, source.cctp.token)
      && isSameAddress(intent.destinationToken, destination.cctp.token)
      && send.value === 0n
      && intent.sourceDecimals === 6
      && intent.destinationDecimals === 6,
      'Untrusted CCTP route',
    );
    const burn = CCTP.decodeFunctionData('depositForBurn', send.data);
    assert(
      BigInt(burn[0].toString()) === bridgeAmount - protocolFee
      && Number(burn[1]) === destination.cctp.domain
      && isSameAddress(burn[2], zeroPadValue(intent.recipient, 32))
      && isSameAddress(burn[3], source.cctp.token)
      && isSameAddress(burn[4], ZeroHash)
      && BigInt(burn[0].toString()) - BigInt(burn[5].toString()) >= BigInt(intent.minimum)
      && [1000, 2000].includes(Number(burn[6])),
      'CCTP intent mismatch',
    );
  } else {
    const { asset, output } = findOftRoute(intent, send.target);
    assert(asset && asset.decimals === intent.sourceDecimals, 'Untrusted OFT source');
    assert((route.type === 'OFT_V2') === (asset.kind === 'oft'), 'VT protocol/deployment mismatch');
    assert(output && output.decimals === intent.destinationDecimals, 'Untrusted OFT destination');
    const parsedSend = (asset.kind === 'stargate' ? STARGATE : OFT).parseTransaction({ data: send.data });
    assert(parsedSend, 'Unsupported OFT send');
    const [param, fee, refund] = parsedSend.args;
    const minimum
      = (BigInt(param.minAmountLD.toString()) * 10n ** BigInt(output.decimals)) / 10n ** BigInt(asset.decimals);
    assert(
      Number(param.dstEid) === destination.eid
      && isSameAddress(param.to, zeroPadValue(intent.recipient, 32))
      && BigInt(param.amountLD.toString()) === bridgeAmount - protocolFee
      && minimum >= BigInt(intent.minimum)
      && param.composeMsg === '0x'
      && param.oftCmd === '0x'
      && isSameAddress(refund, source.wrapper)
      && BigInt(fee.lzTokenFee.toString()) === 0n
      && send.value === BigInt(fee.nativeFee.toString()) + (isNative ? bridgeAmount - protocolFee : 0n),
      'OFT intent mismatch',
    );
    // Native drops and composed calls grant authority beyond a plain transfer
    assert(isSafeReceiveOptions(param.extraOptions), 'Unsupported OFT execution options');
  }
  const sweep = calls[index++];
  assert(
    sweep && isSameAddress(sweep.target, source.wrapper) && sweep.value === 0n && index === calls.length,
    'Unsupported nested VT calls',
  );
  const cleanup = WRAPPER.decodeFunctionData('sweep', sweep.data);
  const refundTokens = new Set<string>(cleanup[0].map((token: string) => token.toLowerCase()));
  assert(
    refundTokens.has('0x0000000000000000000000000000000000000000')
    && (isNative || refundTokens.has(intent.sourceToken.toLowerCase())),
    'Incomplete VT refund',
  );
  assert(
    isSameAddress(cleanup[1], intent.owner)
    && cleanup[0].length <= 2
    && cleanup[0].every(
      (token: string) =>
        isSameAddress(token, intent.sourceToken)
        || isSameAddress(token, '0x0000000000000000000000000000000000000000'),
    ),
    'Invalid VT refund',
  );
  const value = BigInt(bridge.value ?? '0');
  assert(value === calls.reduce((sum, call) => sum + call.value, 0n), 'VT value mismatch');
  assert(
    value - (isNative ? amount : 0n) <= BigInt(intent.nativeFeeBudget),
    'VT native fee exceeds budget',
  );
  return bridge;
}

function isSameAddress(a: string, b: string) {
  return a.toLowerCase() === b.toLowerCase();
}
function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function isSafeReceiveOptions(options: string): boolean {
  if (options === '0x') return true;
  if (!/^0x0003[0-9a-f]*$/i.test(options)) return false;
  let offset = 6;
  while (offset < options.length) {
    const worker = options.slice(offset, offset + 2);
    const length = parseInt(options.slice(offset + 2, offset + 6), 16);
    const type = options.slice(offset + 6, offset + 8);
    if (worker !== '01' || type !== '01' || ![17, 33].includes(length)) return false;
    const end = offset + 6 + length * 2;
    if (end > options.length) return false;
    if (length === 33 && BigInt('0x' + options.slice(offset + 40, end)) !== 0n) return false;
    offset = end;
  }
  return offset === options.length;
}
