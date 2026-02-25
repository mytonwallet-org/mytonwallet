import {
  type AccountMeta,
  AccountRole,
  type AccountSignerMeta,
  type Address,
  isTransactionSigner as kitIsTransactionSigner,
  type ProgramDerivedAddress,
  type TransactionSigner,
  upgradeRoleToSigner,
} from '@solana/kit';

export type ResolvedAccount<
  T extends string = string,
  U extends Address<T> | ProgramDerivedAddress<T> | TransactionSigner<T> | null = | Address<T>
    | ProgramDerivedAddress<T>
    | TransactionSigner<T>
    | null,
> = {
  isWritable: boolean;
  value: U;
};

export function expectAddress<T extends string = string>(
  value: Address<T> | ProgramDerivedAddress<T> | TransactionSigner<T> | null | undefined,
): Address<T> {
  if (!value) {
    throw new Error('Expected a Address.');
  }
  if (typeof value === 'object' && 'address' in value) {
    return value.address;
  }
  if (Array.isArray(value)) {
    return value[0] as Address<T>;
  }
  return value as Address<T>;
}

export function isTransactionSigner<TAddress extends string = string>(
  value: Address<TAddress> | ProgramDerivedAddress<TAddress> | TransactionSigner<TAddress>,
): value is TransactionSigner<TAddress> {
  return !!value && typeof value === 'object' && 'address' in value && kitIsTransactionSigner(value);
}

export function getAccountMetaFactory(programAddress: Address, optionalAccountStrategy: 'omitted' | 'programId') {
  return (account: ResolvedAccount): AccountMeta | AccountSignerMeta | undefined => {
    if (!account.value) {
      if (optionalAccountStrategy === 'omitted') return;
      return Object.freeze({ address: programAddress, role: AccountRole.READONLY });
    }

    const writableRole = account.isWritable ? AccountRole.WRITABLE : AccountRole.READONLY;
    return Object.freeze({
      address: expectAddress(account.value),
      role: isTransactionSigner(account.value) ? upgradeRoleToSigner(writableRole) : writableRole,
      ...(isTransactionSigner(account.value) ? { signer: account.value } : {}),
    });
  };
}
