import {
  bumpZcashFeePerByteForZip317,
  estimateZcashConventionalFee,
  getZcashConventionalFeeFromLogicalActions,
  getZcashTransparentLogicalActions,
} from './zcashZip317';

describe('zcashZip317', () => {
  it('matches ZIP-317 grace minimum for a typical 1-in 2-out transfer', () => {
    const logicalActions = getZcashTransparentLogicalActions(150, 68);
    expect(logicalActions).toBe(2);
    expect(getZcashConventionalFeeFromLogicalActions(logicalActions)).toBe(10000n);
    expect(estimateZcashConventionalFee(1, 2)).toBe(10000n);
  });

  it('scales with additional standard inputs', () => {
    expect(estimateZcashConventionalFee(5, 2)).toBe(25000n);
  });

  it('bumps feePerByte when coin selection underpays ZIP-317', () => {
    const bumped = bumpZcashFeePerByteForZip317(38n, 6780n, 10000n);
    expect(bumped * 226n).toBeGreaterThanOrEqual(10000n);
  });
});
