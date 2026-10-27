import { toBase64Address } from '../../../chains/ton/util/tonCore';
import { isTransferPayloadDangerous } from './index';

const SIGNER = `0:${'5'.repeat(64)}`;
const OTHER = `0:${'6'.repeat(64)}`;

function startAuction(beneficiaryAddress: string) {
  return {
    type: 'teleitem:start-auction' as const,
    queryId: 0n,
    nftAddress: `0:${'1'.repeat(64)}`,
    beneficiaryAddress,
    initialMinBid: 2_000_000_000n,
    maxBid: 0n,
    minBidStep: 5,
    minExtendTime: 3600,
    duration: 86400,
  };
}

describe('isTransferPayloadDangerous', () => {
  it('treats unknown payloads as dangerous', () => {
    expect(isTransferPayloadDangerous({ type: 'unknown', base64: 'AA==' }, SIGNER)).toBe(true);
  });

  it('does not flag a start-auction that pays the signer', () => {
    expect(isTransferPayloadDangerous(
      startAuction(toBase64Address(SIGNER, true, 'mainnet')),
      SIGNER,
    )).toBe(false);
  });

  it('flags a start-auction whose beneficiary is not the signer', () => {
    expect(isTransferPayloadDangerous(startAuction(OTHER), SIGNER)).toBe(true);
  });

  it('flags a start-auction when the signer address is missing', () => {
    expect(isTransferPayloadDangerous(startAuction(SIGNER))).toBe(true);
  });

  it('does not flag a first-bid deploy that pays Fragment', () => {
    expect(isTransferPayloadDangerous({
      type: 'teleitem:deploy',
      tokenName: 'alice',
      beneficiaryAddress: OTHER,
      initialMinBid: 2_000_000_000n,
      maxBid: 0n,
      minBidStep: 5,
      minExtendTime: 3600,
      duration: 86400,
    }, SIGNER)).toBe(false);
  });
});
