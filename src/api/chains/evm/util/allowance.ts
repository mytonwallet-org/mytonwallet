const UINT256_MAX = (1n << 256n) - 1n;
const UINT160_MAX = (1n << 160n) - 1n;
const UINT128_MAX = (1n << 128n) - 1n;

/**
 * Smallest allowance still treated as ERC-20 "infinite".
 * Top 32 bits of uint256 — leaves room for large post-approve decrements while
 * staying far above any realistic finite approval.
 */
const UINT256_INFINITE_FLOOR = 1n << 224n;

/**
 * Smallest allowance still treated as Permit2 "infinite".
 * Top 32 bits of uint160 — Permit2 spends subtract from allowance on each transfer.
 */
const UINT160_INFINITE_FLOOR = 1n << 128n;

/**
 * Detects protocol "infinite" allowances across ERC-20 and Permit2.
 * Uses explicit max sentinels and uint160/uint256 high-bit floors instead of a
 * single uint256 percentage threshold (Permit2 max is uint160.max).
 */
export function isUnlimitedEvmAllowance(allowance: bigint): boolean {
  if (allowance <= 0n) return false;

  if (
    allowance === UINT256_MAX
    || allowance === UINT160_MAX
    || allowance === UINT128_MAX
  ) {
    return true;
  }

  if (allowance >= UINT256_INFINITE_FLOOR || allowance >= UINT160_INFINITE_FLOOR) {
    return true;
  }

  return false;
}
