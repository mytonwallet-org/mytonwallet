/** ZIP-317 conventional fee (Revision 0/1; transparent-only spends). */
const MARGINAL_FEE_ZAT = 5000n;
const GRACE_ACTIONS = 2;
const P2PKH_STANDARD_INPUT_SIZE = 150;
const P2PKH_STANDARD_OUTPUT_SIZE = 34;

/** Typical signed P2PKH input in a v5 tx (coin selection vsize is lower than full v5 size). */
const SIGNED_P2PKH_INPUT_BYTES = 148;

/** Coin-selection vsize overhead (@scure/btc-signer omits the Zcash v5 header and bundle tail). */
const COIN_SELECTION_VSIZE_OVERHEAD = 50n;

export function getZcashTransparentLogicalActions(
  txInTotalSize: number,
  txOutTotalSize: number,
): number {
  const fromInputs = Math.ceil(txInTotalSize / P2PKH_STANDARD_INPUT_SIZE);
  const fromOutputs = Math.ceil(txOutTotalSize / P2PKH_STANDARD_OUTPUT_SIZE);

  return Math.max(fromInputs, fromOutputs);
}

export function getZcashConventionalFeeFromLogicalActions(logicalActions: number): bigint {
  const actions = Math.max(GRACE_ACTIONS, logicalActions);

  return MARGINAL_FEE_ZAT * BigInt(actions);
}

/** ZIP-317 minimum fee from signed transparent section sizes (ZIP-317 uses actual `tx_in` / `tx_out` bytes). */
export function estimateZcashConventionalFee(inputCount: number, outputCount: number): bigint {
  const logicalActions = getZcashTransparentLogicalActions(
    inputCount * SIGNED_P2PKH_INPUT_BYTES,
    outputCount * P2PKH_STANDARD_OUTPUT_SIZE,
  );

  return getZcashConventionalFeeFromLogicalActions(logicalActions);
}

function getCoinSelectionVsizeEstimate(inputCount: number, outputCount: number): bigint {
  return COIN_SELECTION_VSIZE_OVERHEAD
    + BigInt(inputCount) * BigInt(SIGNED_P2PKH_INPUT_BYTES)
    + BigInt(outputCount) * BigInt(P2PKH_STANDARD_OUTPUT_SIZE);
}

/** Fee rate (zat/vB) so @scure/btc-signer change subtraction meets ZIP-317 for this shape. */
export function getZcashZip317FeePerByte(inputCount: number, outputCount: number): bigint {
  const minFee = estimateZcashConventionalFee(inputCount, outputCount);
  const estimatedVsize = getCoinSelectionVsizeEstimate(inputCount, outputCount);

  return (minFee + estimatedVsize - 1n) / estimatedVsize;
}

/** Raises feePerByte when coin selection underpaid relative to ZIP-317. */
export function bumpZcashFeePerByteForZip317(
  feePerByte: bigint,
  selectedFee: bigint,
  minFee: bigint,
): bigint {
  if (selectedFee <= 0n || selectedFee >= minFee) {
    return feePerByte;
  }

  return (minFee * feePerByte) / selectedFee + 1n;
}

export function resolveZcashFeePerByte(
  baseFeePerByte: bigint,
  inputCount: number,
  outputCount: number,
): bigint {
  const zip317FeePerByte = getZcashZip317FeePerByte(inputCount, outputCount);

  return baseFeePerByte > zip317FeePerByte ? baseFeePerByte : zip317FeePerByte;
}
