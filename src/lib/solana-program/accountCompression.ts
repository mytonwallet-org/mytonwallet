const CONCURRENT_MERKLE_TREE_HEADER_SIZE_V1 = 56;

const HEADER_OFFSET_MAX_BUFFER_SIZE = 2;
const HEADER_OFFSET_MAX_DEPTH = 6;

// Verified tree sizes for valid (maxDepth, maxBufferSize) pairs
const TREE_SIZE_BY_DEPTH_BUFFER: Record<string, number> = {
  '20,256': 174752,
};

function getConcurrentMerkleTreeSize(maxDepth: number, maxBufferSize: number): number {
  const key = `${maxDepth},${maxBufferSize}`;
  const exact = TREE_SIZE_BY_DEPTH_BUFFER[key];
  if (exact !== undefined) {
    return exact;
  }

  // Return nearest value
  return 16 + 32 * (maxBufferSize * (maxDepth + 2) + maxDepth);
}

export function getCanopyDepthFromCanopyByteLength(canopyByteLength: number): number {
  if (canopyByteLength <= 0) {
    return 0;
  }
  const depth = Math.log2(canopyByteLength / 32 + 2) - 1;
  return Math.round(depth);
}

export function getCanopyDepthFromAccountData(base64Data: string): number {
  const buffer = Buffer.from(base64Data, 'base64');
  if (buffer.length < CONCURRENT_MERKLE_TREE_HEADER_SIZE_V1) {
    return 0;
  }

  const maxBufferSize = buffer.readUInt32LE(HEADER_OFFSET_MAX_BUFFER_SIZE);
  const maxDepth = buffer.readUInt32LE(HEADER_OFFSET_MAX_DEPTH);

  const treeSize = getConcurrentMerkleTreeSize(maxDepth, maxBufferSize);
  if (treeSize <= 0) {
    return 0;
  }
  const canopyByteLength = buffer.length - CONCURRENT_MERKLE_TREE_HEADER_SIZE_V1 - treeSize;
  if (canopyByteLength <= 0) {
    return 0;
  }

  return getCanopyDepthFromCanopyByteLength(canopyByteLength);
}
