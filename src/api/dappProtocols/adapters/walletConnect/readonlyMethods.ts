// Read-only EVM JSON-RPC methods we forward through the wallet's backend RPC
// for injected dApps (wagmi/viem-based clients call these as part of their
// preflight). Sign and send methods are deliberately excluded — they must go
// through `sendTransaction` / `signData` which surface the user-confirmation UI.
//
// The wallet adapter enforces this set as a security boundary; client-side
// copies (see EvmConnector.ts) avoid round-trips for clearly unsupported
// methods. Native injection scripts (Air iOS Swift, Air Android Kotlin) must
// mirror this list manually — they run in contexts that cannot import TS modules.
export const READONLY_EVM_RPC_METHODS: ReadonlySet<string> = new Set([
  'eth_blockNumber',
  'eth_getBalance',
  'eth_call',
  'eth_estimateGas',
  'eth_gasPrice',
  'eth_maxPriorityFeePerGas',
  'eth_feeHistory',
  'eth_getTransactionCount',
  'eth_getTransactionByHash',
  'eth_getTransactionReceipt',
  'eth_getCode',
  'eth_getStorageAt',
  'eth_getBlockByNumber',
  'eth_getBlockByHash',
  'eth_getLogs',
  'eth_getBlockTransactionCountByNumber',
  'eth_getBlockTransactionCountByHash',
  'eth_protocolVersion',
  'eth_syncing',
  'net_listening',
  'web3_clientVersion',
]);
