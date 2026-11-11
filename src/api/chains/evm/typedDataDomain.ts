const EIP712_DOMAIN_FIELDS = [
  { name: 'name', type: 'string' },
  { name: 'version', type: 'string' },
  { name: 'chainId', type: 'uint256' },
  { name: 'verifyingContract', type: 'address' },
  { name: 'salt', type: 'bytes32' },
];

export function buildTypedDataDomainType(domain: Record<string, unknown>) {
  return EIP712_DOMAIN_FIELDS.filter(({ name }) => {
    const value = domain[name];
    // eslint-disable-next-line no-null/no-null -- ethers omits nullish domain values
    return value !== null && value !== undefined;
  });
}

export function isValidTypedDataDomain(domain: Record<string, unknown>): boolean {
  return Object.entries(domain).every(([name, value]) => {
    // eslint-disable-next-line no-null/no-null -- ethers omits nullish domain values
    return value === null || value === undefined || EIP712_DOMAIN_FIELDS.some((field) => field.name === name);
  });
}
