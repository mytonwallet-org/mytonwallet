import type { TradeAction } from './review.js';
const getgemsBlockers: Readonly<Record<TradeAction,string>> = Object.freeze({
  buy:'No approved on-chain atomic price cap or reviewed immutable-price implementation',
  list:'Exact deployment, recipient and custody semantics are not approved for execution',
  'cancel-sale':'Cancellation and NFT return lineage are not approved for execution',
  'make-offer':'Deployment expenses and offer principal coverage are not proven without prefunding',
  'accept-offer':'NFT/collection offer ABI, conditions, remaining quantity and final settlement require review',
  'cancel-offer':'Offer refund lineage and concurrent acceptance are not approved for execution',
});
/** Wallet-owned gate. Marketplace JSON, a version string or a successful RPC recheck cannot
 * enable execution. REST parsing/building and local contract tests remain available separately.
 * Replacing this disabled table requires implementation + evidence, not a remote boolean.
 */
export function getgemsExecutionCapability(action: TradeAction): Readonly<{ enabled:false; reason:string }> {
  if (!Object.hasOwn(getgemsBlockers,action)) throw Error('Unknown trade action');
  return Object.freeze({enabled:false,reason:getgemsBlockers[action]});
}
export function requireProviderExecution(provider:string,action:TradeAction): void {
  if (provider==='getgems') throw Error(`Getgems execution blocked: ${getgemsExecutionCapability(action).reason}`);
  if (provider!=='wallet-market') throw Error('Unknown trading provider');
  // Own-market laboratory sessions are checked by their isolated emulator adapter.
  // This gate does not approve any provider for production signing.
}
