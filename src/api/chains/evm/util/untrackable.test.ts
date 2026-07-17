import { UntrackableRegistry } from './untrackable';

describe('UntrackableRegistry', () => {
  let currentTime: number;
  const now = () => currentTime;
  const advance = (ms: number) => {
    currentTime += ms;
  };

  beforeEach(() => {
    currentTime = 1_000_000;
  });

  it('reports unmarked addresses as trackable', () => {
    const registry = new UntrackableRegistry({ now });
    expect(registry.has('mainnet', '0xabc')).toBe(false);
  });

  it('remembers a marked address within the TTL', () => {
    const registry = new UntrackableRegistry({ ttlMs: 1000, now });
    registry.mark('mainnet', '0xabc');
    advance(999);
    expect(registry.has('mainnet', '0xabc')).toBe(true);
  });

  it('forgets a marked address once the TTL elapses', () => {
    const registry = new UntrackableRegistry({ ttlMs: 1000, now });
    registry.mark('mainnet', '0xabc');
    advance(1000);
    expect(registry.has('mainnet', '0xabc')).toBe(false);
  });

  it('is case-insensitive on the address (EIP-55 checksummed vs lowercase)', () => {
    const registry = new UntrackableRegistry({ now });
    registry.mark('mainnet', '0xAbCdEf0000000000000000000000000000000001');
    expect(registry.has('mainnet', '0xabcdef0000000000000000000000000000000001')).toBe(true);
  });

  it('isolates verdicts by network', () => {
    const registry = new UntrackableRegistry({ now });
    registry.mark('mainnet', '0xabc');
    expect(registry.has('testnet', '0xabc')).toBe(false);
  });

  it('reset clears all verdicts', () => {
    const registry = new UntrackableRegistry({ now });
    registry.mark('mainnet', '0xabc');
    registry.reset();
    expect(registry.has('mainnet', '0xabc')).toBe(false);
  });
});
