/**
 * Copied from /src/api/chains/ton/util/tonCore.ts as tree shaking did not work for some reason.
 */

import { Address, Builder, Cell } from '@ton/core';

import { JettonOpCode } from '../../api/chains/ton/constants';
import { generateQueryId } from '../../api/chains/ton/util';

interface TokenTransferBodyParams {
  queryId?: bigint;
  tokenAmount: bigint;
  toAddress: string;
  responseAddress: string;
  forwardAmount?: bigint;
  forwardPayload?: Cell;
  /**
   * `forwardPayload` can be stored either at a tail of the root cell (i.e. inline) or as its ref.
   * This option forbids the inline variant. This requires more gas but safer.
   */
  noInlineForwardPayload?: boolean;
  customPayload?: Cell;
}

const TON_MAX_COMMENT_BYTES = 127;

// Copied from /src/api/chains/ton/util/tonCore.ts as tree shaking did not work for some reason
export function buildTokenTransferBody(params: TokenTransferBodyParams) {
  const {
    queryId,
    tokenAmount,
    toAddress,
    responseAddress,
    forwardAmount,
    forwardPayload,
    noInlineForwardPayload,
    customPayload,
  } = params;

  // Schema definition: https://github.com/ton-blockchain/TEPs/blob/0d7989fba6f2d9cb08811bf47263a9b314dc5296/text/0074-jettons-standard.md#1-transfer
  let builder = new Builder()
    .storeUint(JettonOpCode.Transfer, 32)
    .storeUint(queryId ?? generateQueryId(), 64)
    .storeCoins(tokenAmount)
    .storeAddress(Address.parse(toAddress))
    .storeAddress(Address.parse(responseAddress))
    .storeMaybeRef(customPayload)
    .storeCoins(forwardAmount ?? 0n);

  builder = storeInlineOrRefCell(builder, forwardPayload, 0, noInlineForwardPayload);

  return builder.endCell();
}

/**
 * Writes a cell to the builder in the `Either Cell ^Cell` TL-B format.
 *
 * @see https://docs.ton.org/v3/documentation/data-formats/tlb/types#either How Either is stored
 */
export function storeInlineOrRefCell(builder: Builder, cell?: Cell, marginBits = 0, noInline?: boolean) {
  if (
    cell
    && !noInline
    && cell.bits.length <= builder.availableBits - marginBits - 1 // 1 for `storeBit`
    && cell.refs.length <= builder.availableRefs
  ) {
    return builder
      .storeBit(0)
      .storeSlice(cell.beginParse(true));
  }

  return builder.storeMaybeRef(cell);
}

export function commentToBytes(comment: string): Uint8Array {
  const buffer = Buffer.from(comment);
  const bytes = new Uint8Array(buffer.length + 4);

  const startBuffer = Buffer.alloc(4);
  startBuffer.writeUInt32BE(0);
  bytes.set(startBuffer, 0);
  bytes.set(buffer, 4);

  return bytes;
}

// Copied from /src/api/chains/ton/util/tonCore.ts as tree shaking did not work for some reason
export function packBytesAsSnakeCell(bytes: Uint8Array): Cell {
  const bytesPerCell = TON_MAX_COMMENT_BYTES;
  const cellCount = Math.ceil(bytes.length / bytesPerCell);
  let headCell: Cell | undefined;

  for (let i = cellCount - 1; i >= 0; i--) {
    const cellOffset = i * bytesPerCell;
    const cellLength = Math.min(bytesPerCell, bytes.length - cellOffset);
    const cellBuffer = Buffer.from(bytes.buffer, bytes.byteOffset + cellOffset, cellLength); // This creates a buffer that references the input bytes instead of copying them

    const nextHeadCell = new Builder().storeBuffer(cellBuffer);
    if (headCell) {
      nextHeadCell.storeRef(headCell);
    }
    headCell = nextHeadCell.endCell();
  }

  return headCell ?? Cell.EMPTY;
}
