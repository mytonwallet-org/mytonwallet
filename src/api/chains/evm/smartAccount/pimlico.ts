export type PimlicoEip7702Auth = {
  address: string;
  chainId: string;
  nonce: string;
  r: string;
  s: string;
  yParity: string;
};

export function buildPimlicoEip7702AuthStub(
  delegate: string,
  chainId: bigint,
  authorizationNonce: bigint,
): PimlicoEip7702Auth {
  return {
    address: delegate,
    chainId: `0x${chainId.toString(16)}`,
    nonce: `0x${authorizationNonce.toString(16)}`,
    r: '0xfffffffffffffffffffffffffffffff000000000000000000000000000000000',
    s: '0x7aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    yParity: '0x1',
  };
}
