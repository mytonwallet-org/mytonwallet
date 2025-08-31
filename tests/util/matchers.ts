import { Address, Cell } from '@ton/core';

/**
 * Jest doesn't match the addresses in simple `expect(address1).toEqual(address2)`.
 * Use `expect(expectAddress(address1)).toEqual(address2)` instead.
 */
export function expectAddress(expectedAddress: Address): any {
  return {
    asymmetricMatch(actualAddress: unknown) {
      return actualAddress instanceof Address && actualAddress.equals(expectedAddress);
    },
  } satisfies jest.AsymmetricMatcher;
}

/**
 * Sometimes Jest doesn't match `Cell` identical instances. Use this function if it happens.
 */
export function expectCell(expectedCell: Cell): any {
  return {
    asymmetricMatch(actualCell: unknown) {
      return actualCell instanceof Cell && actualCell.equals(expectedCell);
    },
  } satisfies jest.AsymmetricMatcher;
}
