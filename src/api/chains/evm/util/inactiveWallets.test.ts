import { InactiveWalletRegistry } from './inactiveWallets';

describe('InactiveWalletRegistry', () => {
  let currentTime: number;
  const now = () => currentTime;
  const advance = (ms: number) => {
    currentTime += ms;
  };

  beforeEach(() => {
    currentTime = 1_000_000;
  });

  it('forgets a marked address immediately', () => {
    const registry = new InactiveWalletRegistry({ now });
    registry.mark('mainnet', 'base', '0xabc');
    registry.forget('mainnet', 'base', '0xabc');
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(false);
  });

  it('reports an unmarked address as worth asking about', () => {
    const registry = new InactiveWalletRegistry({ now });
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(false);
  });

  it('remembers a marked address within the TTL', () => {
    const registry = new InactiveWalletRegistry({ ttlMs: 1000, now });
    registry.mark('mainnet', 'base', '0xabc');
    advance(999);
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(true);
  });

  it('forgets a marked address once the TTL elapses', () => {
    const registry = new InactiveWalletRegistry({ ttlMs: 1000, now });
    registry.mark('mainnet', 'base', '0xabc');
    advance(1000);
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(false);
  });

  // The whole point of keying per chain: the same address is routinely busy on one chain and
  // untouched on another, and a chain-blind verdict would silence the history of the busy one.
  it('keeps the verdict separate per chain', () => {
    const registry = new InactiveWalletRegistry({ now });
    registry.mark('mainnet', 'base', '0xabc');
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(true);
    expect(registry.has('mainnet', 'polygon', '0xabc')).toBe(false);
  });

  it('keeps the verdict separate per network', () => {
    const registry = new InactiveWalletRegistry({ now });
    registry.mark('mainnet', 'base', '0xabc');
    expect(registry.has('testnet', 'base', '0xabc')).toBe(false);
  });

  it('treats address casing as the same address', () => {
    const registry = new InactiveWalletRegistry({ now });
    registry.mark('mainnet', 'base', '0xAbC');
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(true);
  });

  it('evicts the oldest entry once the cap is exceeded', () => {
    const registry = new InactiveWalletRegistry({ maxEntries: 2, now });
    registry.mark('mainnet', 'base', '0x1');
    registry.mark('mainnet', 'base', '0x2');
    registry.mark('mainnet', 'base', '0x3');

    expect(registry.has('mainnet', 'base', '0x1')).toBe(false);
    expect(registry.has('mainnet', 'base', '0x2')).toBe(true);
    expect(registry.has('mainnet', 'base', '0x3')).toBe(true);
  });

  // Re-marking has to move the key to the tail, or the cap evicts a freshly confirmed verdict
  // while a staler one survives.
  it('refreshes recency on a repeated mark', () => {
    const registry = new InactiveWalletRegistry({ maxEntries: 2, now });
    registry.mark('mainnet', 'base', '0x1');
    registry.mark('mainnet', 'base', '0x2');
    registry.mark('mainnet', 'base', '0x1');
    registry.mark('mainnet', 'base', '0x3');

    expect(registry.has('mainnet', 'base', '0x2')).toBe(false);
    expect(registry.has('mainnet', 'base', '0x1')).toBe(true);
    expect(registry.has('mainnet', 'base', '0x3')).toBe(true);
  });

  // Without this the cap can drop the very address the registry is asked about most often,
  // which is exactly the one it exists to keep.
  it('refreshes recency on a read', () => {
    const registry = new InactiveWalletRegistry({ maxEntries: 2, now });
    registry.mark('mainnet', 'base', '0x1');
    registry.mark('mainnet', 'base', '0x2');
    registry.has('mainnet', 'base', '0x1');
    registry.mark('mainnet', 'base', '0x3');

    expect(registry.has('mainnet', 'base', '0x2')).toBe(false);
    expect(registry.has('mainnet', 'base', '0x1')).toBe(true);
    expect(registry.has('mainnet', 'base', '0x3')).toBe(true);
  });

  // A read must not push the expiry out, or an address checked every few minutes would never
  // be re-probed and a funded wallet could stay hidden indefinitely.
  it('leaves the expiry untouched on a read', () => {
    const registry = new InactiveWalletRegistry({ ttlMs: 1000, now });
    registry.mark('mainnet', 'base', '0xabc');
    advance(900);
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(true);
    advance(100);
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(false);
  });

  it('extends the TTL of an address marked again', () => {
    const registry = new InactiveWalletRegistry({ ttlMs: 1000, now });
    registry.mark('mainnet', 'base', '0xabc');
    advance(900);
    registry.mark('mainnet', 'base', '0xabc');
    advance(900);
    expect(registry.has('mainnet', 'base', '0xabc')).toBe(true);
  });
});
