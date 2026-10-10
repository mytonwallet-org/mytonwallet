import type { AgentV2HostContextSnapshot } from './types';

interface AgentV2AssetRefBinding {
  accountId: string;
  slug: string;
  chain: string;
}

export class AgentV2WalletRefRegistry {
  private readonly accountRefById = new Map<string, string>();
  private readonly accountIdByRef = new Map<string, string>();
  private readonly addressRefByKey = new Map<string, string>();
  private readonly addressByRef = new Map<string, string>();
  private readonly contactRefs = new Map<string, string>();
  private readonly assetRefs = new Map<string, string>();
  private readonly assetBindings = new Map<string, AgentV2AssetRefBinding>();
  private readonly assetAccountIds = new Set<string>();

  get accountRefs(): ReadonlyMap<string, string> {
    return this.accountRefById;
  }

  get accountIds(): ReadonlyMap<string, string> {
    return this.accountIdByRef;
  }

  get addressRefs(): ReadonlyMap<string, string> {
    return this.addressRefByKey;
  }

  get addresses(): ReadonlyMap<string, string> {
    return this.addressByRef;
  }

  // Keep account identity for deleted entries while the host still reports their state.
  // Addresses/contacts follow host presence. Asset refs live until their account is removed
  // or deleted: additional positions may refer to assets absent from holdings.
  reconcile(snapshot?: AgentV2HostContextSnapshot) {
    const accountKeys = new Set<string>();
    const addressKeys = new Set<string>();
    const contactKeys = new Set<string>();
    this.assetAccountIds.clear();
    const indexAddress = (key: string, address: string, contactKey = key) => {
      addressKeys.add(key);
      contactKeys.add(contactKey);
      this.getAddressRef(key, address);
      this.getContactRef(contactKey);
    };
    for (const account of snapshot?.accounts ?? []) {
      accountKeys.add(account.accountId);
      this.getAccountRef(account.accountId);
      if (account.state === 'deleted') continue;
      this.assetAccountIds.add(account.accountId);
      for (const [chain, address] of Object.entries(account.addresses)) {
        if (address) indexAddress(walletAddressKey(account.accountId, chain), address);
      }
      for (const holding of account.holdings) {
        this.getAssetRef(account.accountId, holding.asset.slug, holding.asset.chain);
      }
      for (const entry of account.savedAddresses ?? []) {
        indexAddress(accountSavedAddressKey(account.accountId, entry.id), entry.address);
      }
    }
    for (const entry of snapshot?.savedAddresses ?? []) {
      indexAddress(`saved:${entry.id}`, entry.address, entry.id);
    }
    for (const [key, ref] of this.accountRefById) {
      if (accountKeys.has(key)) continue;
      this.accountRefById.delete(key);
      this.accountIdByRef.delete(ref);
    }
    for (const [key, ref] of this.addressRefByKey) {
      if (addressKeys.has(key)) continue;
      this.addressRefByKey.delete(key);
      this.addressByRef.delete(ref);
    }
    for (const key of this.contactRefs.keys()) {
      if (!contactKeys.has(key)) this.contactRefs.delete(key);
    }
    for (const [key, ref] of this.assetRefs) {
      if (this.assetAccountIds.has(this.assetBindings.get(ref)!.accountId)) continue;
      this.assetRefs.delete(key);
      this.assetBindings.delete(ref);
    }
  }

  clear() {
    this.accountRefById.clear();
    this.accountIdByRef.clear();
    this.addressRefByKey.clear();
    this.addressByRef.clear();
    this.contactRefs.clear();
    this.assetRefs.clear();
    this.assetBindings.clear();
    this.assetAccountIds.clear();
  }

  getAccountRef(accountId: string) {
    let ref = this.accountRefById.get(accountId);
    if (!ref) {
      ref = `account_${crypto.randomUUID()}`;
      this.accountRefById.set(accountId, ref);
      this.accountIdByRef.set(ref, accountId);
    }
    return ref;
  }

  private getAddressRef(key: string, address: string) {
    let ref = this.addressRefByKey.get(key);
    if (!ref) {
      ref = `address_${crypto.randomUUID()}`;
      this.addressRefByKey.set(key, ref);
    }
    this.addressByRef.set(ref, address);
    return ref;
  }

  private getContactRef(key: string) {
    let ref = this.contactRefs.get(key);
    if (!ref) {
      ref = `contact_${crypto.randomUUID()}`;
      this.contactRefs.set(key, ref);
    }
    return ref;
  }

  getAssetRef(accountId: string, slug: string, chain: string) {
    if (!this.assetAccountIds.has(accountId)) throw new Error('Wallet reference account is unavailable');
    const key = `${accountId}\0${chain}\0${slug}`;
    let ref = this.assetRefs.get(key);
    if (!ref) {
      ref = `asset_${crypto.randomUUID()}`;
      this.assetRefs.set(key, ref);
    }
    this.assetBindings.set(ref, { accountId, slug, chain });
    return ref;
  }

  resolveAssetRef(assetRef: string) {
    return this.assetBindings.get(assetRef);
  }

  resolveSavedAddressRefs(accountId: string, contactId: string) {
    const key = accountSavedAddressKey(accountId, contactId);
    const contactRef = this.contactRefs.get(key);
    const addressRef = this.addressRefByKey.get(key);
    return contactRef && addressRef ? { contactRef, addressRef } : undefined;
  }

  resolveProfileSavedAddressRefs(contactId: string) {
    const contactRef = this.contactRefs.get(contactId);
    const addressRef = this.addressRefByKey.get(`saved:${contactId}`);
    return contactRef && addressRef ? { contactRef, addressRef } : undefined;
  }

  resolveWalletAddressRefs(accountId: string, chain: string) {
    const key = walletAddressKey(accountId, chain);
    const contactRef = this.contactRefs.get(key);
    const addressRef = this.addressRefByKey.get(key);
    return contactRef && addressRef ? { contactRef, addressRef } : undefined;
  }
}

function accountSavedAddressKey(accountId: string, contactId: string) {
  return `account:${accountId}:saved:${contactId}`;
}

function walletAddressKey(accountId: string, chain: string) {
  return `wallet:${accountId}:${chain}`;
}
